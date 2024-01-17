// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {DeployCCIDRequest} from "../../script/v2/DeployCCIDRequest.s.sol";
import {CCIDRequest} from "../../src/v2/CCIDRequest.sol";
import {HelperRequestConfig} from "../../script/v2/HelperRequestConfig.s.sol";
import {Vm} from "forge-std/Vm.sol";
import {IEverestConsumer} from "@everest/contracts/interfaces/IEverestConsumer.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {Router} from "@chainlink/contracts-ccip/src/v0.8/ccip/Router.sol";
import {LinkToken} from "../mocks/LinkToken.sol";
import {EVM2EVMOnRamp} from "@chainlink/contracts-ccip/src/v0.8/ccip/onRamp/EVM2EVMOnRamp.sol";
import {EVM2EVMOnRampSetup} from "@chainlink/contracts-ccip/src/v0.8/ccip/test/onRamp/EVM2EVMOnRampSetup.t.sol";
import {MockARM} from "@chainlink/contracts-ccip/src/v0.8/ccip/test/mocks/MockARM.sol";
import {IPriceRegistry} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IPriceRegistry.sol";
import {Internal} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Internal.sol";

contract CCIDRequestTest is Test, EVM2EVMOnRampSetup {
    CCIDRequest ccidRequest;
    HelperRequestConfig helperConfig;
    Router router;
    LinkToken link;
    MockARM mockArm;

    address routerAddress;
    address linkAddress;
    address onRampAddress;
    address mockArmAddress;
    address priceRegistryAddress;

    address public REVEALER = makeAddr("REVEALER");
    address public REVEALEE = makeAddr("REVEALEE");
    uint256 public constant STARTING_USER_BALANCE = 1000 ether;
    address public CCID_FULFILL = makeAddr("CCID_FULFILL");
    uint64 public SEPOLIA_CHAIN_SELECTOR = 16015286601757825753; // Sepolia
    uint16 public constant MAX_RET_BYTES = 4 + 4 * 32;

    function setUp() public override {
        DeployCCIDRequest deployer = new DeployCCIDRequest();
        (ccidRequest, helperConfig) = deployer.run();
        (routerAddress, linkAddress, mockArmAddress) = helperConfig.activeNetworkConfig();
        router = Router(routerAddress);
        link = LinkToken(linkAddress);

        EVM2EVMOnRampSetup.setUp();
        EVM2EVMOnRamp.FeeTokenConfigArgs[] memory feeTokenConfigArgs = new EVM2EVMOnRamp.FeeTokenConfigArgs[](1);
        feeTokenConfigArgs[0] = EVM2EVMOnRamp.FeeTokenConfigArgs({
            token: linkAddress,
            networkFeeUSDCents: 10,
            gasMultiplierWeiPerEth: 1e9,
            premiumMultiplierWeiPerEth: 1e9,
            enabled: true
        });
        EVM2EVMOnRamp onRamp = new EVM2EVMOnRamp(
            EVM2EVMOnRamp.StaticConfig({
                linkToken: linkAddress,
                chainSelector: SOURCE_CHAIN_ID,
                destChainSelector: SEPOLIA_CHAIN_SELECTOR,
                defaultTxGasLimit: GAS_LIMIT,
                maxNopFeesJuels: MAX_NOP_FEES_JUELS,
                prevOnRamp: address(0),
                armProxy: address(mockArmAddress)
            }),
            generateDynamicOnRampConfig(address(router), address(s_priceRegistry)),
            getTokensAndPools(s_sourceTokens, getCastedSourcePools()),
            rateLimiterConfig(),
            feeTokenConfigArgs,
            s_tokenTransferFeeConfigArgs,
            getNopsAndWeights()
        );
        onRampAddress = address(onRamp);

        Internal.TokenPriceUpdate[] memory tokenPriceUpdates = new Internal.TokenPriceUpdate[](1);
        tokenPriceUpdates[0] = Internal.TokenPriceUpdate({sourceToken: linkAddress, usdPerToken: 10000000000000000000});
        Internal.GasPriceUpdate[] memory gasPriceUpdates = new Internal.GasPriceUpdate[](1);
        gasPriceUpdates[0] =
            Internal.GasPriceUpdate({destChainSelector: SEPOLIA_CHAIN_SELECTOR, usdPerUnitGas: 500000000000000});
        Internal.PriceUpdates memory priceUpdates =
            Internal.PriceUpdates({tokenPriceUpdates: tokenPriceUpdates, gasPriceUpdates: gasPriceUpdates});
        IPriceRegistry(address(s_priceRegistry)).updatePrices(priceUpdates);
    }

    function test_constructor_sets_values_correctly() public {
        assertEq(address(router), ccidRequest.getRouter());
        assertEq(address(link), address(ccidRequest.i_link()));
    }

    modifier fundLinkToRevealerAndApprove() {
        vm.startPrank(msg.sender);
        link.transfer(REVEALER, STARTING_USER_BALANCE);
        vm.deal(REVEALER, STARTING_USER_BALANCE);
        vm.stopPrank();
        vm.startPrank(REVEALER);
        link.approve(address(ccidRequest), type(uint256).max);
        vm.stopPrank();
        _;
    }

    function test_request_reverts_if_destination_chain_not_allowed() public fundLinkToRevealerAndApprove {
        vm.startPrank(REVEALER);
        vm.expectRevert(
            abi.encodeWithSelector(
                CCIDRequest.CCIDRequest__DestinationChainNotAllowlisted.selector, 16015286601757825753
            )
        );
        ccidRequest.requestCcidStatus(CCID_FULFILL, REVEALEE, SEPOLIA_CHAIN_SELECTOR);
        vm.stopPrank();
    }

    modifier allowDestinationChainSelector() {
        vm.startPrank(msg.sender);
        ccidRequest.allowlistDestinationChain(SEPOLIA_CHAIN_SELECTOR, true);
        vm.stopPrank();
        _;
    }

    modifier applyRampUpdates() {
        vm.startPrank(msg.sender);
        Router.OnRamp memory newOnRamp =
            Router.OnRamp({destChainSelector: SEPOLIA_CHAIN_SELECTOR, onRamp: onRampAddress});
        Router.OnRamp[] memory newOnRampArray = new Router.OnRamp[](1);
        newOnRampArray[0] = newOnRamp;

        router.applyRampUpdates(newOnRampArray, new Router.OffRamp[](0), new Router.OffRamp[](0));
        vm.stopPrank();
        _;
    }

    modifier fundCcidRequest() {
        vm.startPrank(msg.sender);
        link.transfer(address(ccidRequest), STARTING_USER_BALANCE);
        vm.stopPrank();
        _;
    }

    function test_request_works()
        public
        fundLinkToRevealerAndApprove
        allowDestinationChainSelector
        applyRampUpdates
        fundCcidRequest
    {
        vm.startPrank(REVEALER);
        ccidRequest.requestCcidStatus(CCID_FULFILL, REVEALEE, SEPOLIA_CHAIN_SELECTOR);
        vm.stopPrank();
    }

    function test_ccipReceive_reverts_if_source_chain_not_allowed() public {
        vm.startPrank(msg.sender);
        Router.OffRamp memory newOffRamp =
            Router.OffRamp({sourceChainSelector: SEPOLIA_CHAIN_SELECTOR, offRamp: msg.sender});
        Router.OffRamp[] memory newOffRampArray = new Router.OffRamp[](1);
        newOffRampArray[0] = newOffRamp;

        router.applyRampUpdates(new Router.OnRamp[](0), new Router.OffRamp[](0), newOffRampArray);

        Client.Any2EVMMessage memory message = Client.Any2EVMMessage({
            messageId: keccak256(abi.encodePacked("testMessageId")),
            sourceChainSelector: SEPOLIA_CHAIN_SELECTOR,
            sender: abi.encode(CCID_FULFILL),
            data: abi.encode(REVEALEE, IEverestConsumer.Status.HumanAndUnique, 0),
            destTokenAmounts: new Client.EVMTokenAmount[](0)
        });

        (bool success, bytes memory retData) =
            router.routeMessage(message, MAX_RET_BYTES, 2000000000000, address(ccidRequest));

        assertFalse(success);

        if (!success) {
            bytes4 errorSignature =
                bytes4(retData[0]) | (bytes4(retData[1]) >> 8) | (bytes4(retData[2]) >> 16) | (bytes4(retData[3]) >> 24);
            assertEq(errorSignature, CCIDRequest.CCIDRequest__SourceChainNotAllowed.selector);

            bytes memory slicedRetData = new bytes(retData.length - 4);
            for (uint256 i = 4; i < retData.length; i++) {
                slicedRetData[i - 4] = retData[i];
            }
            uint64 sourceChainSelector = abi.decode(slicedRetData, (uint64));
            assertEq(sourceChainSelector, SEPOLIA_CHAIN_SELECTOR);
        }
        vm.stopPrank();
    }

    modifier approveSourceChain() {
        vm.startPrank(msg.sender);
        ccidRequest.allowlistSourceChain(SEPOLIA_CHAIN_SELECTOR, true);
        vm.stopPrank();
        _;
    }

    function test_ccipReceive_reverts_if_source_sender_not_allowed() public approveSourceChain {
        vm.startPrank(msg.sender);
        Router.OffRamp memory newOffRamp =
            Router.OffRamp({sourceChainSelector: SEPOLIA_CHAIN_SELECTOR, offRamp: msg.sender});
        Router.OffRamp[] memory newOffRampArray = new Router.OffRamp[](1);
        newOffRampArray[0] = newOffRamp;

        router.applyRampUpdates(new Router.OnRamp[](0), new Router.OffRamp[](0), newOffRampArray);

        Client.Any2EVMMessage memory message = Client.Any2EVMMessage({
            messageId: keccak256(abi.encodePacked("testMessageId")),
            sourceChainSelector: SEPOLIA_CHAIN_SELECTOR,
            sender: abi.encode(CCID_FULFILL),
            data: abi.encode(REVEALEE, IEverestConsumer.Status.HumanAndUnique, 0),
            destTokenAmounts: new Client.EVMTokenAmount[](0)
        });

        (bool success, bytes memory retData) =
            router.routeMessage(message, MAX_RET_BYTES, 2000000000000, address(ccidRequest));

        assertFalse(success);

        if (!success) {
            bytes4 errorSignature =
                bytes4(retData[0]) | (bytes4(retData[1]) >> 8) | (bytes4(retData[2]) >> 16) | (bytes4(retData[3]) >> 24);
            assertEq(errorSignature, CCIDRequest.CCIDRequest__SenderNotAllowed.selector);

            bytes memory slicedRetData = new bytes(retData.length - 4);
            for (uint256 i = 4; i < retData.length; i++) {
                slicedRetData[i - 4] = retData[i];
            }
            address sender = abi.decode(slicedRetData, (address));
            assertEq(sender, CCID_FULFILL);
        }
        vm.stopPrank();
    }

    modifier approveSourceSender() {
        vm.startPrank(msg.sender);
        ccidRequest.allowlistSender(CCID_FULFILL, true);
        vm.stopPrank();
        _;
    }

    function test_ccipReceive_works() public approveSourceChain approveSourceSender {
        vm.startPrank(msg.sender);
        Router.OffRamp memory newOffRamp =
            Router.OffRamp({sourceChainSelector: SEPOLIA_CHAIN_SELECTOR, offRamp: msg.sender});
        Router.OffRamp[] memory newOffRampArray = new Router.OffRamp[](1);
        newOffRampArray[0] = newOffRamp;

        router.applyRampUpdates(new Router.OnRamp[](0), new Router.OffRamp[](0), newOffRampArray);

        Client.Any2EVMMessage memory message = Client.Any2EVMMessage({
            messageId: keccak256(abi.encodePacked("testMessageId")),
            sourceChainSelector: SEPOLIA_CHAIN_SELECTOR,
            sender: abi.encode(CCID_FULFILL),
            data: abi.encode(REVEALEE, IEverestConsumer.Status.HumanAndUnique, 0),
            destTokenAmounts: new Client.EVMTokenAmount[](0)
        });

        router.routeMessage(message, MAX_RET_BYTES, 2000000000000, address(ccidRequest));
        vm.stopPrank();
    }
}
