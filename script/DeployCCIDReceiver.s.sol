// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

import {Script} from "forge-std/Script.sol";
import {CCIDReceiver} from "../src/CCIDReceiver.sol";
import {HelperReceiverConfig} from "./HelperReceiverConfig.s.sol";
import {Router} from "@chainlink/contracts/src/v0.8/ccip/Router.sol";

contract DeployCCIDReceiver is Script {
    function run() external returns (CCIDReceiver, HelperReceiverConfig) {
        HelperReceiverConfig config = new HelperReceiverConfig();
        (address router, uint256 deployerKey) = config.activeNetworkConfig();

        vm.startBroadcast(deployerKey);
        CCIDReceiver ccidReceiver = new CCIDReceiver(router);
        vm.stopBroadcast();
        return (ccidReceiver, config);
    }
}
