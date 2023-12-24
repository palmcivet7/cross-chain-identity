// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {Script} from "forge-std/Script.sol";
import {Router} from "@chainlink/contracts-ccip/src/v0.8/ccip/Router.sol";
import {MockARM} from "@chainlink/contracts-ccip/src/v0.8/ccip/test/mocks/MockARM.sol";
import {WETH9} from "@chainlink/contracts-ccip/src/v0.8/ccip/test/WETH9.sol";
import {LinkToken} from "../../test/mocks/LinkToken.sol";

contract HelperRequestConfig is Script {
    struct NetworkConfig {
        address router;
        address link;
        address mockArm;
    }

    NetworkConfig public activeNetworkConfig;

    constructor() {
        if (block.chainid == 11155111) {
            activeNetworkConfig = getSepoliaEthConfig();
        } else if (block.chainid == 5) {
            activeNetworkConfig = getGoerliEthConfig();
        } else if (block.chainid == 43113) {
            activeNetworkConfig = getFujiConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }

    function getSepoliaEthConfig() public pure returns (NetworkConfig memory) {
        return NetworkConfig({
            router: 0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59, // https://docs.chain.link/ccip/supported-networks#ethereum-sepolia
            link: 0x779877A7B0D9E8603169DdbD7836e478b4624789, // https://sepolia.etherscan.io/token/0x779877a7b0d9e8603169ddbd7836e478b4624789
            mockArm: address(0)
        });
    }

    function getGoerliEthConfig() public pure returns (NetworkConfig memory) {
        return NetworkConfig({
            router: address(0), // not available on ccip
            link: 0x326C977E6efc84E512bB9C30f76E30c160eD06FB, // https://static-assets.everest.org/web/images/HowToSetupAndUseTheEverestChainlinkService.pdf#page=8
            mockArm: address(0)
        });
    }

    function getFujiConfig() public pure returns (NetworkConfig memory) {
        return NetworkConfig({
            router: 0xF694E193200268f9a4868e4Aa017A0118C9a8177,
            link: 0x0b9d5D9136855f6FEc3c0993feE6E9CE8a297846,
            mockArm: address(0)
        });
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        vm.startBroadcast();
        WETH9 weth9 = new WETH9();
        MockARM mockArm = new MockARM();
        Router router = new Router(address(weth9), address(mockArm));
        LinkToken mockLink = new LinkToken();
        vm.stopBroadcast();

        return NetworkConfig({router: address(router), link: address(mockLink), mockArm: address(mockArm)});
    }
}
