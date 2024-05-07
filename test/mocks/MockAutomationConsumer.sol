// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {IAutomationRegistryConsumer} from
    "@chainlink/contracts-ccip/src/v0.8/automation/interfaces/IAutomationRegistryConsumer.sol";

contract MockAutomationConsumer is IAutomationRegistryConsumer {
    uint96 private s_minBalance = 1 * 1e17;

    function setMinBalance(uint96 _newMinBalance) external {
        s_minBalance = _newMinBalance;
    }

    function getBalance(uint256 id) external view returns (uint96 balance) {}

    function getMinBalance(uint256 id) external view returns (uint96 minBalance) {
        return s_minBalance;
    }

    function cancelUpkeep(uint256 id) external {}

    function pauseUpkeep(uint256 id) external {}

    function unpauseUpkeep(uint256 id) external {}

    function addFunds(uint256 id, uint96 amount) external {}

    function withdrawFunds(uint256 id, address to) external {}
}
