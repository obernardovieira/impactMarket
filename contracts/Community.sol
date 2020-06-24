// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.6.0;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @notice Welcome to the Community contract. For each community
 * there will be one contract like this being deployed by
 * ImpactMarket contract. This enable us to save tokens on the
 * contract itself, and avoid the problems of having everything
 * in one single contract. Each community has it's own members and
 * and managers.
 */
contract Community is AccessControl {
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    enum BeneficiaryState {NONE, Valid, Locked, Removed} // starts by 0 (when user is not added yet)

    mapping(address => uint256) public cooldown;
    mapping(address => uint256) public lastInterval;
    mapping(address => uint256) public claimed;
    mapping(address => BeneficiaryState) public beneficiaries;

    uint256 public amountByClaim;
    uint256 public baseIntervalTime;
    uint256 public incIntervalTime;
    uint256 public claimHardCap;

    address public cUSDAddress;
    bool public locked;

    event ManagerAdded(address indexed _account);
    event ManagerRemoved(address indexed _account);
    event BeneficiaryAdded(address indexed _account);
    event BeneficiaryLocked(address indexed _account);
    event BeneficiaryUnlocked(address indexed _account);
    event BeneficiaryRemoved(address indexed _account);
    event BeneficiaryClaim(address indexed _account, uint256 _amount);
    event CommunityEdited(
        address indexed _cUSD,
        uint256 _amountByClaim,
        uint256 _baseIntervalTime,
        uint256 _incIntervalTime,
        uint256 _claimHardCap
    );
    event CommunityLocked(address indexed _by);
    event CommunityUnlocked(address indexed _by);

    /**
     * @dev Constructor with custom fields, choosen by the community.
     * @param _firstManager Comminuty's first manager. Will
     * be able to add others.
     * @param _amountByClaim Base amount to be claim by the benificiary.
     * @param _baseIntervalTime Base interval to start claiming.
     * @param _incIntervalTime Increment interval used in each claim.
     * @param _claimHardCap Limit that a beneficiary can claim at once.
     * @param _cUSDAddress cUSD smart contract address.
     */
    constructor(
        address _firstManager,
        uint256 _amountByClaim,
        uint256 _baseIntervalTime,
        uint256 _incIntervalTime,
        uint256 _claimHardCap,
        address _cUSDAddress
    ) public {
        require(_baseIntervalTime > _incIntervalTime, "");
        require(_claimHardCap > _amountByClaim, "");

        _setupRole(MANAGER_ROLE, _firstManager);
        _setRoleAdmin(MANAGER_ROLE, MANAGER_ROLE);
        emit ManagerAdded(_firstManager);

        amountByClaim = _amountByClaim;
        baseIntervalTime = _baseIntervalTime;
        incIntervalTime = _incIntervalTime;
        claimHardCap = _claimHardCap;

        cUSDAddress = _cUSDAddress;
        locked = false;
    }

    modifier onlyValidBeneficiary() {
        require(beneficiaries[msg.sender] != BeneficiaryState.Locked, "LOCKED");
        require(
            beneficiaries[msg.sender] != BeneficiaryState.Removed,
            "REMOVED"
        );
        require(
            beneficiaries[msg.sender] == BeneficiaryState.Valid,
            "NOT_BENEFICIARY"
        );
        _;
    }

    modifier onlyManagers() {
        require(hasRole(MANAGER_ROLE, msg.sender), "NOT_MANAGER");
        _;
    }

    // TODO: remove
    function isManager(address _account) external view returns (bool) {
        return hasRole(MANAGER_ROLE, _account);
    }

    /**
     * @dev Allow community managers to add other managers.
     */
    function addManager(address _account) external onlyManagers {
        grantRole(MANAGER_ROLE, _account);
        emit ManagerAdded(_account);
    }

    /**
     * @dev Allow community managers to remove other managers.
     */
    function removeManager(address _account) external onlyManagers {
        revokeRole(MANAGER_ROLE, _account);
        emit ManagerRemoved(_account);
    }

    /**
     * @dev Allow community managers to add beneficiaries.
     */
    function addBeneficiary(address _account) external onlyManagers {
        beneficiaries[_account] = BeneficiaryState.Valid;
        cooldown[_account] = block.timestamp;
        lastInterval[_account] = uint256(baseIntervalTime - incIntervalTime);
        emit BeneficiaryAdded(_account);
    }

    /**
     * @dev Allow community managers to lock beneficiaries.
     */
    function lockBeneficiary(address _account) external onlyManagers {
        require(beneficiaries[_account] == BeneficiaryState.Valid, "NOT_YET");
        beneficiaries[_account] = BeneficiaryState.Locked;
        emit BeneficiaryLocked(_account);
    }

    /**
     * @dev Allow community managers to unlock locked beneficiaries.
     */
    function unlockBeneficiary(address _account) external onlyManagers {
        require(beneficiaries[_account] == BeneficiaryState.Locked, "NOT_YET");
        beneficiaries[_account] = BeneficiaryState.Valid;
        emit BeneficiaryUnlocked(_account);
    }

    /**
     * @dev Allow community managers to add beneficiaries.
     */
    function removeBeneficiary(address _account) external onlyManagers {
        beneficiaries[_account] = BeneficiaryState.Removed;
        emit BeneficiaryRemoved(_account);
    }

    /**
     * @dev Allow beneficiaries to claim.
     */
    function claim() external onlyValidBeneficiary {
        require(!locked, "LOCKED");
        require(cooldown[msg.sender] <= block.timestamp, "NOT_YET");
        require(
            (claimed[msg.sender] + amountByClaim) <= claimHardCap,
            "MAX_CLAIM"
        );
        claimed[msg.sender] = claimed[msg.sender] + amountByClaim;
        lastInterval[msg.sender] = lastInterval[msg.sender] + incIntervalTime;
        cooldown[msg.sender] = uint256(
            block.timestamp + lastInterval[msg.sender]
        );
        emit BeneficiaryClaim(msg.sender, amountByClaim);
        bool success = IERC20(cUSDAddress).transfer(msg.sender, amountByClaim);
        require(success, "");
    }

    /**
     * @dev Allow community managers to edit community variables.
     */
    function edit(
        uint256 _amountByClaim,
        uint256 _baseIntervalTime,
        uint256 _incIntervalTime,
        uint256 _claimHardCap,
        address _cUSDAddress
    ) external onlyManagers {
        require(_baseIntervalTime > _incIntervalTime, "");
        require(_claimHardCap > _amountByClaim, "");

        amountByClaim = _amountByClaim;
        baseIntervalTime = _baseIntervalTime;
        incIntervalTime = _incIntervalTime;
        claimHardCap = _claimHardCap;

        cUSDAddress = _cUSDAddress;
        emit CommunityEdited(
            _cUSDAddress,
            _amountByClaim,
            _baseIntervalTime,
            _incIntervalTime,
            _claimHardCap
        );
    }

    /**
     * Allow community managers to lock community claims.
     */
    function lock() external onlyManagers {
        locked = true;
        emit CommunityLocked(msg.sender);
    }

    /**
     * Allow community managers to unlock community claims.
     */
    function unlock() external onlyManagers {
        locked = false;
        emit CommunityUnlocked(msg.sender);
    }

    /**
     * Migrate funds in current community to new one (temporary version).
     */
    function migrateFunds(address _newCommunity) external onlyManagers {
        // TODO: planning
        uint256 balance = IERC20(cUSDAddress).balanceOf(address(this));
        bool success = IERC20(cUSDAddress).transfer(_newCommunity, balance);
        require(success, "");
    }
}
