// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";

/// @title IMetadataValidator
/// @notice Interface for metadata validation
interface IMetadataValidator {
    function validate(
        string calldata schemaType,
        string calldata schemaVersion,
        bytes calldata metadata
    ) external view returns (bool);
}

/// @title ViridianMetadataStorage
/// @notice Implements flexible storage system with IPFS integration
contract ViridianMetadataStorage is AccessControl {
    struct MetadataEntry {
        bytes32 id;
        string schemaType;
        string schemaVersion;
        string ipfsHash;
        address owner;
        uint256 timestamp;
        bool verified;
    }

    // Storage mappings
    mapping(bytes32 => MetadataEntry) public entries;
    mapping(address => bytes32[]) public entriesByOwner;
    
    // Validator registry
    mapping(string => address) public validators;
    
    // Events
    event MetadataStored(bytes32 indexed id, string schemaType, string ipfsHash);
    event MetadataVerified(bytes32 indexed id);
    
    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }
    
    /// @notice Store metadata with IPFS integration
    /// @param _schemaType Type of metadata schema
    /// @param _schemaVersion Version of schema
    /// @param _ipfsHash IPFS hash of metadata
    function store(
        string calldata _schemaType,
        string calldata _schemaVersion,
        string calldata _ipfsHash
    ) external returns (bytes32) {
        require(bytes(_ipfsHash).length > 0, "Invalid IPFS hash");
        
        bytes32 id = keccak256(abi.encodePacked(
            block.timestamp,
            msg.sender,
            _ipfsHash
        ));
        
        entries[id] = MetadataEntry({
            id: id,
            schemaType: _schemaType,
            schemaVersion: _schemaVersion,
            ipfsHash: _ipfsHash,
            owner: msg.sender,
            timestamp: block.timestamp,
            verified: false
        });
        
        entriesByOwner[msg.sender].push(id);
        
        emit MetadataStored(id, _schemaType, _ipfsHash);
        return id;
    }
    
    /// @notice Retrieve metadata entry
    /// @param _id Metadata identifier
    function retrieve(bytes32 _id) external view returns (MetadataEntry memory) {
        return entries[_id];
    }
    
    /// @notice Update existing metadata
    /// @param _id Metadata identifier
    /// @param _newIpfsHash New IPFS hash
    function update(bytes32 _id, string calldata _newIpfsHash) external {
        MetadataEntry storage entry = entries[_id];
        require(entry.owner == msg.sender, "Not owner");
        
        entry.ipfsHash = _newIpfsHash;
        entry.timestamp = block.timestamp;
        entry.verified = false;
        
        emit MetadataStored(_id, entry.schemaType, _newIpfsHash);
    }
    
    /// @notice Register validator for schema type
    /// @param _schemaType Schema type identifier
    /// @param _validator Validator contract address
    function registerValidator(
        string calldata _schemaType,
        address _validator
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        validators[_schemaType] = _validator;
    }
    
    /// @notice Verify metadata against registered validator
    /// @param _id Metadata identifier
    function verify(bytes32 _id) external {
        MetadataEntry storage entry = entries[_id];
        require(!entry.verified, "Already verified");
        
        address validator = validators[entry.schemaType];
        require(validator != address(0), "No validator");
        
        // Convert IPFS hash to metadata bytes (implementation needed)
        bytes memory metadata = ipfsHashToBytes(entry.ipfsHash);
        
        bool valid = IMetadataValidator(validator).validate(
            entry.schemaType,
            entry.schemaVersion,
            metadata
        );
        
        require(valid, "Invalid metadata");
        entry.verified = true;
        
        emit MetadataVerified(_id);
    }
    
    /// @notice Convert IPFS hash to bytes
    /// @param _ipfsHash IPFS hash string
    function ipfsHashToBytes(string memory _ipfsHash) 
        internal 
        pure 
        returns (bytes memory) 
    {
        // Implementation needed - convert IPFS hash to original bytes
        return "";
    }
}