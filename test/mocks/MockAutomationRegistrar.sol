// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {IAutomationRegistrar, RegistrationParams} from "../../src/v2/interfaces/IAutomationRegistrar.sol";

contract MockAutomationRegistrar is IAutomationRegistrar {
    uint256 private upkeepId;

    function registerUpkeep(RegistrationParams calldata) external returns (uint256) {
        return upkeepId++;
    }
}
