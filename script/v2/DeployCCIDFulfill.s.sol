// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {Script} from "forge-std/Script.sol";
import {CCIDFulfill} from "../../src/v2/CCIDFulfill.sol";
import {HelperFulfillConfig} from "./HelperFulfillConfig.s.sol";

contract DeployCCIDFulfill is Script {
    function run() external returns (CCIDFulfill, HelperFulfillConfig) {
        HelperFulfillConfig config = new HelperFulfillConfig();

        (
            address router,
            address link,
            address consumer,
            address automationConsumer,
            address automationRegistrar,
            address ccidRequest,
            uint64 chainSelector,
        ) = config.activeNetworkConfig();

        vm.startBroadcast();
        CCIDFulfill ccidFulfill =
            new CCIDFulfill(router, link, consumer, automationConsumer, automationRegistrar, ccidRequest, chainSelector);
        vm.stopBroadcast();
        return (ccidFulfill, config);
    }
}
