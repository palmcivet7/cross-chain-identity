// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

import {Script} from "forge-std/Script.sol";
import {CCIDSender} from "../../src/v1/CCIDSender.sol";
import {HelperSenderConfig} from "./HelperSenderConfig.s.sol";

contract DeployCCIDSender is Script {
    function run() external returns (CCIDSender, HelperSenderConfig) {
        HelperSenderConfig config = new HelperSenderConfig();

        (
            address router,
            address link,
            address oracle,
            string memory jobId,
            uint256 oraclePayment,
            string memory signUpUrl,
            uint256 deployerKey,
        ) = config.activeNetworkConfig();

        vm.startBroadcast(deployerKey);
        CCIDSender ccidSender = new CCIDSender(router, link, oracle, jobId, oraclePayment, signUpUrl);
        vm.stopBroadcast();
        return (ccidSender, config);
    }
}
