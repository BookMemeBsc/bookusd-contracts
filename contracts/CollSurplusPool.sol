// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;

import "./Interfaces/ICollSurplusPool.sol";
import "./Interfaces/IBOOKToken.sol";
import "./Dependencies/SafeMath.sol";
import "./Dependencies/Ownable.sol";
import "./Dependencies/CheckContract.sol";
import "./Dependencies/console.sol";

contract CollSurplusPool is Ownable, CheckContract, ICollSurplusPool {
    using SafeMath for uint256;

    string public constant NAME = "CollSurplusPool";

    address public borrowerOperationsAddress;
    address public troveManagerAddress;
    address public activePoolAddress;

    IBOOKToken public book;

    // deposited ether tracker
    uint256 internal ETH;
    // Collateral surplus claimable by trove owners
    mapping(address => uint) internal balances;

    // --- Events ---

    event BorrowerOperationsAddressChanged(address _newBorrowerOperationsAddress);
    event TroveManagerAddressChanged(address _newTroveManagerAddress);
    event ActivePoolAddressChanged(address _newActivePoolAddress);
    event BOOKAddressChanged(address _book);

    event CollBalanceUpdated(address indexed _account, uint _newBalance);
    event EtherSent(address _to, uint _amount);

    // --- Contract setters ---

    function setAddresses(
        address _borrowerOperationsAddress,
        address _troveManagerAddress,
        address _activePoolAddress,
        address _book
    ) external override onlyOwner {
        checkContract(_borrowerOperationsAddress);
        checkContract(_troveManagerAddress);
        checkContract(_activePoolAddress);
        checkContract(_book);

        borrowerOperationsAddress = _borrowerOperationsAddress;
        troveManagerAddress = _troveManagerAddress;
        activePoolAddress = _activePoolAddress;
        book = IBOOKToken(_book);

        emit BorrowerOperationsAddressChanged(_borrowerOperationsAddress);
        emit TroveManagerAddressChanged(_troveManagerAddress);
        emit ActivePoolAddressChanged(_activePoolAddress);
        emit BOOKAddressChanged(_book);

        _renounceOwnership();
    }

    /* Returns the ETH state variable at ActivePool address.
       Not necessarily equal to the raw ether balance - ether can be forcibly sent to contracts. */
    function getETH() external view override returns (uint) {
        return ETH;
    }

    function getCollateral(address _account) external view override returns (uint) {
        return balances[_account];
    }

    // --- Pool functionality ---

    function accountSurplus(address _account, uint _amount) external override {
        _requireCallerIsTroveManager();

        uint newAmount = balances[_account].add(_amount);
        balances[_account] = newAmount;

        emit CollBalanceUpdated(_account, newAmount);
    }

    function claimColl(address _account) external override {
        _requireCallerIsBorrowerOperations();
        uint claimableColl = balances[_account];
        require(claimableColl > 0, "CollSurplusPool: No collateral available to claim");

        balances[_account] = 0;
        emit CollBalanceUpdated(_account, 0);

        ETH = ETH.sub(claimableColl);
        emit EtherSent(_account, claimableColl);

        bool success = book.transfer(_account, claimableColl);
        require(success, "CollSurplusPool: sending BOOK failed");
    }

    // --- 'require' functions ---

    function _requireCallerIsBorrowerOperations() internal view {
        require(msg.sender == borrowerOperationsAddress, "CollSurplusPool: Caller is not Borrower Operations");
    }

    function _requireCallerIsTroveManager() internal view {
        require(msg.sender == troveManagerAddress, "CollSurplusPool: Caller is not TroveManager");
    }

    function _requireCallerIsActivePool() internal view {
        require(msg.sender == activePoolAddress, "CollSurplusPool: Caller is not Active Pool");
    }

    function addETH(uint _amount) external override {
        _requireCallerIsTroveManager();
        ETH = ETH.add(_amount);
    }

    // --- Fallback function ---

    receive() external payable {}
}
