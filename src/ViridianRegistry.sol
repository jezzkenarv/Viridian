// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {ERC20} from "@allo-v2/lib/solady/src/tokens/ERC20.sol";
import {Metadata} from "@allo-v2/contracts/core/libraries/Metadata.sol";
import {Anchor} from "@allo-v2/contracts/core/Anchor.sol";

/// @title ViridianRegistry
/// @notice Extension of Allo Registry for environmental impact projects with token integration
contract ViridianRegistry is Initializable, AccessControlUpgradeable {
    // Service categories for environmental tokens
    enum ServiceCategory {
        CARBON_REDUCTION,
        BIODIVERSITY,
        WATER_QUALITY,
        SOIL_HEALTH,
        ECOSYSTEM_RESTORATION
    }

    // Market configuration for ecosystem services
    struct MarketConfig {
        uint256 basePrice;
        uint256 reserveRatio;
        uint256 minSupply;
        uint256 maxSupply;
        bool isActive;
    }

    // Token parameters for future AMM integration
    struct TokenParams {
        bytes32 profileId;
        string name;
        string symbol;
        uint256 initialSupply;
        uint256 maxMintable;
        mapping(ServiceCategory => uint256) serviceAllocation;
        bool isInitialized;
    }

    // Core Profile structure from Allo with environmental extensions
    struct Profile {
        bytes32 id;             // Unique identifier
        uint256 nonce;          // Nonce used for ID generation
        string name;            // Profile name
        Metadata metadata;      // IPFS metadata using Allo's struct
        address owner;          // Profile owner
        address anchor;         // Associated Anchor contract
        ServiceCategory[] services;  // Supported ecosystem services
        bytes32 tokenParamsId;      // Reference to token parameters
        bool isTokenized;           // Tokenization status
    }

    // Storage mappings from Allo Registry
    mapping(address => bytes32) public anchorToProfileId;
    mapping(bytes32 => Profile) public profilesById;
    mapping(bytes32 => address) public profileIdToPendingOwner;
    
    // Additional Viridian storage
    mapping(ServiceCategory => MarketConfig) public marketConfigs;
    mapping(bytes32 => TokenParams) public tokenParams;
    mapping(ServiceCategory => bytes32[]) public profilesByService;
    
    // Roles
    bytes32 public constant ALLO_OWNER = keccak256("ALLO_OWNER");
    bytes32 public constant MARKET_OPERATOR = keccak256("MARKET_OPERATOR");
    bytes32 public constant VALIDATOR = keccak256("VALIDATOR");

    // Events aligned with Allo + environmental extensions
    event ProfileCreated(
        bytes32 indexed profileId,
        uint256 nonce,
        string name,
        Metadata metadata,
        address owner,
        address anchor,
        ServiceCategory[] services
    );
    event ProfileMetadataUpdated(bytes32 indexed profileId, Metadata metadata);
    event ProfileNameUpdated(bytes32 indexed profileId, string name, address anchor);
    event ProfileOwnerUpdated(bytes32 indexed profileId, address owner);
    event ServiceAdded(bytes32 indexed profileId, ServiceCategory indexed category);
    event MarketConfigUpdated(ServiceCategory indexed category, uint256 basePrice, uint256 reserveRatio);
    event TokenParametersSet(bytes32 indexed profileId, string name, string symbol);

    modifier onlyProfileOwner(bytes32 _profileId) {
        _checkOnlyProfileOwner(_profileId);
        _;
    }

    /// @notice Initialize the registry
    /// @param _owner Contract owner address
    function initialize(address _owner) external reinitializer(1) {
        if (_owner == address(0)) revert("ZERO_ADDRESS");
        
        _grantRole(ALLO_OWNER, _owner);
        _grantRole(MARKET_OPERATOR, _owner);

        // Initialize market configurations
        marketConfigs[ServiceCategory.CARBON_REDUCTION] = MarketConfig({
            basePrice: 1e18,
            reserveRatio: 500000,
            minSupply: 1000e18,
            maxSupply: 1000000e18,
            isActive: false
        });
    }

    /// @notice Create a new profile with environmental services
    /// @param _nonce Unique nonce for profile generation
    /// @param _name Profile name
    /// @param _metadata IPFS metadata using Allo's format
    /// @param _services Array of supported ecosystem services
    /// @param _tokenName Token name for future issuance
    /// @param _tokenSymbol Token symbol for future issuance
    /// @param _members Array of profile members
    function createProfile(
        uint256 _nonce,
        string memory _name,
        Metadata memory _metadata,
        ServiceCategory[] memory _services,
        string memory _tokenName,
        string memory _tokenSymbol,
        address[] memory _members
    ) external returns (bytes32) {
        bytes32 profileId = _generateProfileId(_nonce, msg.sender);
        
        if (profilesById[profileId].anchor != address(0)) revert("NONCE_NOT_AVAILABLE");
        if (_services.length == 0) revert("NO_SERVICES");

        // Generate anchor using Allo's pattern
        address anchor = _generateAnchor(profileId, _name);

        // Create profile
        Profile storage profile = profilesById[profileId];
        profile.id = profileId;
        profile.nonce = _nonce;
        profile.name = _name;
        profile.metadata = _metadata;
        profile.owner = msg.sender;
        profile.anchor = anchor;
        profile.services = _services;
        profile.isTokenized = false;

        // Set up token parameters
        bytes32 tokenParamsId = keccak256(abi.encodePacked(profileId, "token"));
        TokenParams storage params = tokenParams[tokenParamsId];
        params.profileId = profileId;
        params.name = _tokenName;
        params.symbol = _tokenSymbol;
        params.isInitialized = true;
        profile.tokenParamsId = tokenParamsId;

        // Map anchor to profileId (Allo compatibility)
        anchorToProfileId[anchor] = profileId;

        // Register services and emit events
        for (uint256 i = 0; i < _services.length; i++) {
            ServiceCategory service = _services[i];
            profilesByService[service].push(profileId);
            emit ServiceAdded(profileId, service);
        }

        // Add members with role-based access
        if (_members.length > 0) {
            for (uint256 i = 0; i < _members.length; i++) {
                if (_members[i] == address(0)) revert("ZERO_ADDRESS");
                _grantRole(profileId, _members[i]);
            }
        }

        emit ProfileCreated(
            profileId,
            _nonce,
            _name,
            _metadata,
            msg.sender,
            anchor,
            _services
        );

        emit TokenParametersSet(profileId, _tokenName, _tokenSymbol);

        return profileId;
    }

    /// @notice Set service allocations for project token
    function setServiceAllocations(
        bytes32 _profileId,
        ServiceCategory[] calldata _services,
        uint256[] calldata _allocations
    ) external onlyProfileOwner(_profileId) {
        Profile storage profile = profilesById[_profileId];
        require(!profile.isTokenized, "ALREADY_TOKENIZED");
        require(_services.length == _allocations.length, "LENGTH_MISMATCH");
        
        TokenParams storage params = tokenParams[profile.tokenParamsId];
        uint256 totalAllocation = 0;
        
        for (uint256 i = 0; i < _services.length; i++) {
            params.serviceAllocation[_services[i]] = _allocations[i];
            totalAllocation += _allocations[i];
        }
        
        require(totalAllocation == 100, "INVALID_ALLOCATION");
    }

    // Internal functions from Allo Registry
    function _generateProfileId(uint256 _nonce, address _owner) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(_nonce, _owner));
    }

    function _generateAnchor(bytes32 _profileId, string memory _name) internal returns (address) {
        bytes memory encodedData = abi.encode(_profileId, _name);
        bytes memory encodedConstructorArgs = abi.encode(_profileId, address(this));
        bytes memory bytecode = abi.encodePacked(type(Anchor).creationCode, encodedConstructorArgs);
        bytes32 salt = keccak256(encodedData);
        
        address preComputedAddress = address(
            uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(bytecode)))))
        );

        try new Anchor{salt: salt}(_profileId, address(this)) returns (Anchor _anchor) {
            return address(_anchor);
        } catch {
            if (Anchor(payable(preComputedAddress)).profileId() != _profileId) revert("ANCHOR_ERROR");
            return preComputedAddress;
        }
    }

    function _checkOnlyProfileOwner(bytes32 _profileId) internal view {
        if (!_isOwnerOfProfile(_profileId, msg.sender)) revert("UNAUTHORIZED");
    }

    function _isOwnerOfProfile(bytes32 _profileId, address _owner) internal view returns (bool) {
        return profilesById[_profileId].owner == _owner;
    }
}