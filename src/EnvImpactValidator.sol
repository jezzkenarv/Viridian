// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";

/// @title EnvironmentalImpactValidator
/// @notice Validates environmental impact claims for different ecosystem services
contract EnvironmentalImpactValidator is AccessControl {
    bytes32 public constant VALIDATOR_ROLE = keccak256("VALIDATOR_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    // Impact claim structure
    struct ImpactClaim {
        bytes32 id;                  // Unique claim identifier
        bytes32 profileId;           // Associated profile
        string category;             // Service category
        string metric;               // Measurement metric
        string unit;                 // Measurement unit
        int256 value;               // Measured value (can be negative for some metrics)
        uint256 timestamp;          // Measurement timestamp
        string location;            // Geographic location
        string methodology;         // Measurement methodology
        bytes32 evidenceHash;       // Hash of supporting evidence
        address validator;          // Address of validator
        bool isVerified;           // Verification status
        uint256 confidenceScore;   // Confidence score (0-100)
    }

    // Validation parameters
    struct ValidationParams {
        int256 minValue;
        int256 maxValue;
        uint256 maxAge;             // Maximum age of measurement in seconds
        string[] requiredEvidence;  // Required evidence types
        bool allowNegative;        // Whether negative values are allowed
    }

    // Storage
    mapping(bytes32 => ImpactClaim) public claims;
    mapping(string => ValidationParams) public categoryParams;
    mapping(string => mapping(string => bool)) public validUnits;
    mapping(string => string[]) public validMethodologies;
    
    // Event declarations
    event ClaimSubmitted(bytes32 indexed claimId, bytes32 indexed profileId, string category);
    event ClaimValidated(bytes32 indexed claimId, address indexed validator, uint256 confidenceScore);
    event ValidationParamsUpdated(string indexed category);
    event UnitAdded(string indexed category, string unit);
    event MethodologyAdded(string indexed category, string methodology);

    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(VALIDATOR_ROLE, msg.sender);

        // Initialize carbon reduction parameters
        categoryParams["carbon_reduction"] = ValidationParams({
            minValue: 0,
            maxValue: 1000000000000,  // 1M tonnes CO2e
            maxAge: 365 days,
            requiredEvidence: new string[](3),
            allowNegative: false
        });
        categoryParams["carbon_reduction"].requiredEvidence[0] = "methodology_documentation";
        categoryParams["carbon_reduction"].requiredEvidence[1] = "measurement_data";
        categoryParams["carbon_reduction"].requiredEvidence[2] = "third_party_verification";

        // Add valid units for carbon reduction
        validUnits["carbon_reduction"]["tCO2e"] = true;
        validUnits["carbon_reduction"]["kgCO2e"] = true;

        // Add valid methodologies for carbon reduction
        validMethodologies["carbon_reduction"].push("GHG_Protocol");
        validMethodologies["carbon_reduction"].push("ISO_14064");
        validMethodologies["carbon_reduction"].push("VCS_VM0015");

        // Initialize biodiversity parameters
        categoryParams["biodiversity"] = ValidationParams({
            minValue: -100,         // Allow negative for biodiversity loss
            maxValue: 100000,       // Maximum species count
            maxAge: 180 days,
            requiredEvidence: new string[](3),
            allowNegative: true
        });
        // Add similar initialization for other categories
    }

    /// @notice Submit a new impact claim
    /// @param profileId Associated profile identifier
    /// @param category Service category
    /// @param metric Measurement metric
    /// @param unit Measurement unit
    /// @param value Measured value
    /// @param location Geographic location
    /// @param methodology Measurement methodology
    /// @param evidenceHash Hash of supporting evidence
    function submitClaim(
        bytes32 profileId,
        string calldata category,
        string calldata metric,
        string calldata unit,
        int256 value,
        string calldata location,
        string calldata methodology,
        bytes32 evidenceHash
    ) external returns (bytes32) {
        require(validateCategory(category), "Invalid category");
        require(validateUnit(category, unit), "Invalid unit");
        require(validateMethodology(category, methodology), "Invalid methodology");
        require(validateValue(category, value), "Invalid value");

        bytes32 claimId = keccak256(abi.encodePacked(
            profileId,
            category,
            block.timestamp,
            msg.sender
        ));

        claims[claimId] = ImpactClaim({
            id: claimId,
            profileId: profileId,
            category: category,
            metric: metric,
            unit: unit,
            value: value,
            timestamp: block.timestamp,
            location: location,
            methodology: methodology,
            evidenceHash: evidenceHash,
            validator: address(0),
            isVerified: false,
            confidenceScore: 0
        });

        emit ClaimSubmitted(claimId, profileId, category);
        return claimId;
    }

    /// @notice Validate an impact claim
    /// @param claimId Claim identifier
    /// @param confidenceScore Validation confidence score (0-100)
    function validateClaim(
        bytes32 claimId,
        uint256 confidenceScore
    ) external onlyRole(VALIDATOR_ROLE) {
        require(confidenceScore <= 100, "Invalid confidence score");
        
        ImpactClaim storage claim = claims[claimId];
        require(!claim.isVerified, "Already verified");
        require(validateAge(claim.category, claim.timestamp), "Claim too old");

        claim.isVerified = true;
        claim.validator = msg.sender;
        claim.confidenceScore = confidenceScore;

        emit ClaimValidated(claimId, msg.sender, confidenceScore);
    }

    // Internal validation functions
    function validateCategory(string memory category) internal view returns (bool) {
        return categoryParams[category].maxAge > 0;
    }

    function validateUnit(string memory category, string memory unit) 
        internal 
        view 
        returns (bool) 
    {
        return validUnits[category][unit];
    }

    function validateMethodology(string memory category, string memory methodology) 
        internal 
        view 
        returns (bool) 
    {
        string[] memory validMethods = validMethodologies[category];
        for (uint i = 0; i < validMethods.length; i++) {
            if (keccak256(abi.encodePacked(validMethods[i])) == 
                keccak256(abi.encodePacked(methodology))) {
                return true;
            }
        }
        return false;
    }

    function validateValue(string memory category, int256 value) 
        internal 
        view 
        returns (bool) 
    {
        ValidationParams memory params = categoryParams[category];
        if (!params.allowNegative && value < 0) return false;
        return value >= params.minValue && value <= params.maxValue;
    }

    function validateAge(string memory category, uint256 timestamp) 
        internal 
        view 
        returns (bool) 
    {
        return (block.timestamp - timestamp) <= categoryParams[category].maxAge;
    }

    // Admin functions for managing validation parameters
    function updateValidationParams(
        string calldata category,
        int256 minValue,
        int256 maxValue,
        uint256 maxAge,
        string[] calldata requiredEvidence,
        bool allowNegative
    ) external onlyRole(ADMIN_ROLE) {
        categoryParams[category] = ValidationParams({
            minValue: minValue,
            maxValue: maxValue,
            maxAge: maxAge,
            requiredEvidence: requiredEvidence,
            allowNegative: allowNegative
        });
        emit ValidationParamsUpdated(category);
    }

    function addUnit(
        string calldata category,
        string calldata unit
    ) external onlyRole(ADMIN_ROLE) {
        validUnits[category][unit] = true;
        emit UnitAdded(category, unit);
    }

    function addMethodology(
        string calldata category,
        string calldata methodology
    ) external onlyRole(ADMIN_ROLE) {
        validMethodologies[category].push(methodology);
        emit MethodologyAdded(category, methodology);
    }
}