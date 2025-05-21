// SPDX-License-Identifier: MIT
pragma solidity 0.6.11;

import "./Interfaces/ILUSDToken.sol";
import "./Interfaces/IBOOKToken.sol";
import "./Interfaces/ITroveManager.sol";
import "./Interfaces/ITwapOracle.sol";

interface IHintHelper {
    function getRedemptionHints(
        uint _LUSDamount,
        uint _price,
        uint _maxIterations
    ) external view returns (address firstRedemptionHint, uint partialRedemptionHintNICR, uint truncatedLUSDamount);

    function getApproxHint(
        uint _CR,
        uint _numTrials,
        uint _inputRandomSeed
    ) external view returns (address hintAddress, uint diff, uint latestRandomSeed);
}

contract RedeemProxy {
    IBOOKToken public constant BOOK = IBOOKToken(0xC9Ad421f96579AcE066eC188a7Bba472fB83017F);
    ILUSDToken public constant BUD = ILUSDToken(0xc28957E946AC244612BcB205C899844Cbbcb093D);
    IHintHelper public constant hintHelper = IHintHelper(0xa3dd985a59cfA95E4353B4Ecf0Fc803327B7cE63);
    ITwapOracle public constant oracle = ITwapOracle(0x7B30280DDEB0514b587b3a9Bd178C9dF9293bb23);
    ITroveManager public constant troveManager = ITroveManager(0xFe5D0aBb0C4Addbb57186133b6FDb7E1FAD1aC15);

    uint32 public twapDuration;

    // --- Events ---
    event RedeemCollateral(address indexed user, uint256 budAmount, uint256 bookAmount);

    constructor(uint32 _twapDuration) public {
        twapDuration = _twapDuration;
    }

    function redeemCollateral(
        uint256 _amount,
        uint256 _maxIterations,
        uint256 _maxFee,
        address _upperHint,
        address _lowerHint
    ) external {
        require(_amount > 0, "RedeemProxy: amount must be greater than 0");

        BUD.transferFrom(msg.sender, address(this), _amount);

        // Get hints for redemption
        (address firstRedemptionHint, uint256 partialRedemptionHintNICR, uint256 truncatedAmount) = getRedemptionHints(
            _amount,
            _maxIterations
        );

        // Get approx hint
        // address approxHint = getApproxHint(partialRedemptionHintNICR);

        // // Get insert position
        // (address upperHint, address lowerHint) = getInsertPosition(partialRedemptionHintNICR, approxHint);

        // Do redemption
        troveManager.redeemCollateral(
            truncatedAmount,
            firstRedemptionHint,
            _upperHint,
            _lowerHint,
            partialRedemptionHintNICR,
            _maxIterations,
            _maxFee
        );

        uint256 bookAmount = BOOK.balanceOf(address(this));
        uint256 budRemaining = BUD.balanceOf(address(this));

        emit RedeemCollateral(msg.sender, _amount - budRemaining, bookAmount);

        _returnBOOK(bookAmount);
        if (budRemaining > 0) _returnBUD(budRemaining);
    }

    function bookTwapPrice() internal view returns (uint256) {
        return oracle.consult(twapDuration);
    }

    function getRedemptionHints(
        uint256 _amount,
        uint256 _maxIterations
    ) internal view returns (address firstRedemptionHint, uint256 partialRedemptionHintNICR, uint256 truncatedAmount) {
        uint256 price = bookTwapPrice();
        return hintHelper.getRedemptionHints(_amount, price, _maxIterations);
    }

    function _returnBUD(uint256 _amount) internal {
        BUD.transfer(msg.sender, _amount);
    }

    function _returnBOOK(uint256 _amount) internal {
        BOOK.transfer(msg.sender, _amount);
    }
}
