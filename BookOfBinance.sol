// SPDX-License-Identifier: MIT

// Book of Binance
// www.bookofbinance.com

// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.22;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract BookOfBinance is ERC20, ERC20Permit, Ownable {
    address public burningBooks;

    constructor() ERC20("Book of Binance", "BOOK") Ownable(msg.sender) ERC20Permit("Book of Binance") {
        _mint(msg.sender, 420000000 * 10 ** decimals());
    }

    modifier onlyBurningBooks() {
        require(burningBooks == msg.sender, "caller is not the operator");
        _;
    }

    function setBurningBooks(address _address) public onlyOwner {
        burningBooks = _address;
    }

    function burn(uint256 _amount) public {
        _burn(msg.sender, _amount);
    }

    function burnFrom(address _account, uint256 _amount) public onlyBurningBooks {
        _burn(_account, _amount);
    }
}
