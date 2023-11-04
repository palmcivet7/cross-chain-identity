// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import {CCIPReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";

contract CCIDReceiver is CCIPReceiver {
    event KYCStatusReceived(string status);

    constructor(address _router) CCIPReceiver(_router) {}

    function _ccipReceive(Client.Any2EVMMessage memory message) external override {
        string memory status = abi.decode(message.data, (string));
        emit KYCStatusReceived(status);
    }
}
