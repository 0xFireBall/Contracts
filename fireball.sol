// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts@4.9.3/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts@4.9.3/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts@4.9.3/access/Ownable.sol";

contract FIREBALL is ERC20, ERC20Burnable, Ownable {
    uint256 public constant MAX_SUPPLY = 3_000_000 * 10**18;

    constructor() ERC20("FIREBALL", "$FIRE") {
        _mint(msg.sender, MAX_SUPPLY);
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual override {
        if (from != address(0) && to != address(0)) {
            uint256 burnAmount = (amount * 1) / 100;
            uint256 sendAmount = amount - burnAmount;
            super._burn(from, burnAmount);
            super._beforeTokenTransfer(from, to, sendAmount);
        } else {
            super._beforeTokenTransfer(from, to, amount);
        }
    }

    function renounceOwnership() public override onlyOwner {
        _transferOwnership(address(0));
    }
}
