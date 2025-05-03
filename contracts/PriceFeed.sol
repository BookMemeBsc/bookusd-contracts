// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;

import "./Interfaces/IPriceFeed.sol";
import "./Interfaces/ITwapOracle.sol";
// import "./Dependencies/SafeMath.sol";
import "./Dependencies/Ownable.sol";
import "./Dependencies/CheckContract.sol";
import "./Dependencies/BaseMath.sol";
import "./Dependencies/LiquityMath.sol";

// import "./Dependencies/console.sol";

/*
 * PriceFeed for mainnet deployment, to be connected to Chainlink's live ETH:USD aggregator reference
 * contract, and a wrapper contract TellorCaller, which connects to TellorMaster contract.
 *
 * The PriceFeed uses Chainlink as primary oracle, and Tellor as fallback. It contains logic for
 * switching oracles based on oracle failures, timeouts, and conditions for returning to the primary
 * Chainlink oracle.
 */
contract PriceFeed is Ownable, CheckContract, BaseMath, IPriceFeed {
    using SafeMath for uint256;

    string public constant NAME = "PriceFeed";

    // Core Liquity contracts
    address borrowerOperationsAddress;
    address troveManagerAddress;

    address book;

    // Oracle contract
    ITwapOracle public twapOracle;

    // The last good price seen from an oracle by Liquity
    uint public lastGoodPrice;

    uint32 public twapWindow = 10 minutes;

    event LastGoodPriceUpdated(uint _lastGoodPrice);

    // --- Dependency setters ---

    function setAddresses(address _twapOracle, address _book) external onlyOwner {
        checkContract(_twapOracle);
        checkContract(_book);

        twapOracle = ITwapOracle(_twapOracle);
        book = _book;

        _updateTwapOracle();
    }

    // --- Functions ---

    /*
     * fetchPrice():
     * Returns the latest price obtained from the Oracle. Called by Liquity functions that require a current price.
     *
     * Also callable by anyone externally.
     *
     * Non-view function - it stores the last good price seen by Liquity.
     *
     * Uses a main oracle (Chainlink) and a fallback oracle (Tellor) in case Chainlink fails. If both fail,
     * it uses the last good price seen by Liquity.
     *
     */
    function fetchPrice() external override returns (uint) {
        _updateTwapOracle();
        return lastGoodPrice;
    }

    // --- Helper functions ---

    function _updateTwapOracle() internal {
        // Update oracle here

        uint256 oraclePrice = twapOracle.consult(twapWindow);
        if (oraclePrice > 0) {
            _storePrice(oraclePrice);
        }
    }

    function setTwapWindow(uint32 _twapWindow) external onlyOwner {
        twapWindow = _twapWindow;
    }

    function _storePrice(uint _currentPrice) internal {
        lastGoodPrice = _currentPrice;
        emit LastGoodPriceUpdated(_currentPrice);
    }
}
