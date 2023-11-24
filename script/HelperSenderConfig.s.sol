// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {Router} from "@chainlink/contracts/src/v0.8/ccip/Router.sol";
import {MockARM} from "@chainlink/contracts/src/v0.8/ccip/test/mocks/MockARM.sol";
import {WETH9} from "@chainlink/contracts/src/v0.8/ccip/test/WETH9.sol";
import {LinkToken} from "../test/mocks/LinkToken.sol";
import {Operator} from "../test/mocks/operator/Operator.sol";

contract HelperSenderConfig is Script {
    struct NetworkConfig {
        address router;
        address link;
        address oracle;
        string jobId;
        uint256 oraclePayment;
        string signUpUrl;
        uint256 deployerKey;
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

    function getSepoliaEthConfig() public view returns (NetworkConfig memory) {
        return NetworkConfig({
            router: 0xD0daae2231E9CB96b94C8512223533293C3693Bf, // https://docs.chain.link/ccip/supported-networks#ethereum-sepolia
            link: 0x779877A7B0D9E8603169DdbD7836e478b4624789, // https://sepolia.etherscan.io/token/0x779877a7b0d9e8603169ddbd7836e478b4624789
            oracle: 0x0000000000000000000000000000000000000000, // replace with Sepolia deployment when available
            jobId: "0000000000000000000000000000000", // replace with jobID when available
            oraclePayment: 100000000000000000, // 0.1 LINK
            signUpUrl: "wallet.everest.org",
            deployerKey: vm.envUint("PRIVATE_KEY"),
            mockArm: address(0)
        });
    }

    function getGoerliEthConfig() public view returns (NetworkConfig memory) {
        return NetworkConfig({
            router: 0x0000000000000000000000000000000000000000, // Eth Goerli not available on CCIP
            link: 0x326C977E6efc84E512bB9C30f76E30c160eD06FB, // https://static-assets.everest.org/web/images/HowToSetupAndUseTheEverestChainlinkService.pdf#page=8
            oracle: 0xB9756312523826A566e222a34793E414A81c88E1, // https://static-assets.everest.org/web/images/HowToSetupAndUseTheEverestChainlinkService.pdf#page=8
            jobId: "14f849816fac426abda2992cbf47d2cd", // https://static-assets.everest.org/web/images/HowToSetupAndUseTheEverestChainlinkService.pdf#page=8
            oraclePayment: 100000000000000000, // 0.1 LINK
            signUpUrl: "wallet.everest.org",
            deployerKey: vm.envUint("PRIVATE_KEY"),
            mockArm: address(0)
        });
    }

    function getFujiConfig() public view returns (NetworkConfig memory) {
        return NetworkConfig({
            router: 0x554472a2720E5E7D5D3C817529aBA05EEd5F82D8, // https://docs.chain.link/ccip/supported-networks#avalanche-fuji
            link: 0x0b9d5D9136855f6FEc3c0993feE6E9CE8a297846, // https://testnet.snowtrace.io/token/0x0b9d5d9136855f6fec3c0993fee6e9ce8a297846
            oracle: 0x0000000000000000000000000000000000000000, // replace with Sepolia deployment when available
            jobId: "0000000000000000000000000000000", // replace with jobID when available
            oraclePayment: 100000000000000000, // 0.1 LINK
            signUpUrl: "wallet.everest.org",
            deployerKey: vm.envUint("PRIVATE_KEY"),
            mockArm: address(0)
        });
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        vm.startBroadcast();
        WETH9 weth9 = new WETH9();
        MockARM mockArm = new MockARM();
        Router router = new Router(address(weth9), address(mockArm));
        LinkToken mockLink = new LinkToken();
        Operator operator = new Operator(address(mockLink), msg.sender);
        vm.stopBroadcast();

        return NetworkConfig({
            router: address(router),
            link: address(mockLink),
            oracle: address(operator),
            jobId: "14f849816fac426abda2992cbf47d2cd", // https://static-assets.everest.org/web/images/HowToSetupAndUseTheEverestChainlinkService.pdf#page=8
            oraclePayment: 100000000000000000, // 0.1 LINK
            signUpUrl: "wallet.everest.org",
            deployerKey: vm.envUint("ANVIL_PRIVATE_KEY"),
            mockArm: address(mockArm)
        });
    }
}
