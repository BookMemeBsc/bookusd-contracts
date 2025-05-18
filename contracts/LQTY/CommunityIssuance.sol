// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;

import "../Interfaces/ILQTYToken.sol";
import "../Interfaces/ICommunityIssuance.sol";
import "../Dependencies/BaseMath.sol";
import "../Dependencies/LiquityMath.sol";
import "../Dependencies/Ownable.sol";
import "../Dependencies/CheckContract.sol";
import "../Dependencies/SafeMath.sol";

contract CommunityIssuance is ICommunityIssuance, Ownable, CheckContract, BaseMath {
    using SafeMath for uint;

    // --- Data ---

    string public constant NAME = "CommunityIssuance";

    uint public constant SECONDS_IN_ONE_MINUTE = 60;
    uint public constant SECONDS_IN_ONE_YEAR = 365 * 24 * 60 * 60;
    uint public constant THREE_YEARS = 3 * SECONDS_IN_ONE_YEAR;

    /*
     * The community LQTY supply cap is the starting balance of the Community Issuance contract.
     * It should be minted to this contract by LQTYToken, when the token is deployed.
     *
     * Set to 32M (slightly less than 1/3) of total LQTY supply.
     */
    uint public constant LQTYSupplyCap = 32e24; // 32 million

    ILQTYToken public lqtyToken;

    address public stabilityPoolAddress;

    uint public totalLQTYIssued;
    uint public deploymentTime;

    // --- Events ---

    event LQTYTokenAddressSet(address _lqtyTokenAddress);
    event StabilityPoolAddressSet(address _stabilityPoolAddress);
    event TotalLQTYIssuedUpdated(uint _totalLQTYIssued);

    // --- Functions ---

    constructor() public {
        // deploymentTime = block.timestamp;
    }

    function setAddresses(
        address _lqtyTokenAddress,
        address _stabilityPoolAddress,
        uint256 _startTime
    ) external override onlyOwner {
        require(deploymentTime == 0, "CommunityIssuance: already deployed");

        checkContract(_lqtyTokenAddress);
        checkContract(_stabilityPoolAddress);

        lqtyToken = ILQTYToken(_lqtyTokenAddress);
        stabilityPoolAddress = _stabilityPoolAddress;

        // When LQTYToken deployed, it should have transferred CommunityIssuance's LQTY entitlement
        // uint LQTYBalance = lqtyToken.balanceOf(address(this));
        // assert(LQTYBalance >= LQTYSupplyCap);

        deploymentTime = _startTime;

        emit LQTYTokenAddressSet(_lqtyTokenAddress);
        emit StabilityPoolAddressSet(_stabilityPoolAddress);
    }

    function issueLQTY() external override returns (uint) {
        _requireCallerIsStabilityPool();

        uint latestTotalLQTYIssued = LQTYSupplyCap.mul(_getCumulativeIssuanceFraction()).div(DECIMAL_PRECISION);
        uint issuance = latestTotalLQTYIssued.sub(totalLQTYIssued);

        totalLQTYIssued = latestTotalLQTYIssued;
        emit TotalLQTYIssuedUpdated(latestTotalLQTYIssued);

        return issuance;
    }

    // Linear emission: fraction = min((timePassed / THREE_YEARS), 1)
    function _getCumulativeIssuanceFraction() internal view returns (uint) {
        uint timePassed = block.timestamp.sub(deploymentTime);
        if (timePassed >= THREE_YEARS) {
            return DECIMAL_PRECISION;
        }
        // Linear fraction, scaled to DECIMAL_PRECISION
        return timePassed.mul(DECIMAL_PRECISION).div(THREE_YEARS);
    }

    function sendLQTY(address _account, uint _LQTYamount) external override {
        _requireCallerIsStabilityPool();

        lqtyToken.transfer(_account, _LQTYamount);
    }

    // --- 'require' functions ---

    function _requireCallerIsStabilityPool() internal view {
        require(msg.sender == stabilityPoolAddress, "CommunityIssuance: caller is not SP");
    }
}
