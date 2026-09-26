// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20Expiring} from "./ERC20Expiring.sol";

contract ExpiringToken is ERC20Expiring {
    constructor(string memory name_, string memory symbol_, address holder, uint256 supply)
        ERC20Expiring(name_, symbol_)
    {
        _mint(holder, supply);
    }
}
