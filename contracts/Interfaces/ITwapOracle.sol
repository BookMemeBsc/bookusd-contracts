// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;

interface ITwapOracle {
    function consult(uint32 _duration) external view returns (uint256);
}
