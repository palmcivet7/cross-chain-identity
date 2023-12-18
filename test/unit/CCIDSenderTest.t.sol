// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {DeployCCIDSender} from "../../script/DeployCCIDSender.s.sol";
import {CCIDSender} from "../../src/v1/CCIDSender.sol";
import {HelperSenderConfig} from "../../script/HelperSenderConfig.s.sol";
import {Vm} from "forge-std/Vm.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {Router} from "@chainlink/contracts-ccip/src/v0.8/ccip/Router.sol";
import {LinkToken} from "../mocks/LinkToken.sol";
import {Operator} from "../mocks/operator/Operator.sol";
import {IEverestConsumer} from "@everest/contracts/interfaces/IEverestConsumer.sol";
import {EVM2EVMOnRamp} from "@chainlink/contracts-ccip/src/v0.8/ccip/onRamp/EVM2EVMOnRamp.sol";
import {EVM2EVMOnRampSetup} from "@chainlink/contracts-ccip/src/v0.8/ccip/test/onRamp/EVM2EVMOnRampSetup.t.sol";
import {MockARM} from "@chainlink/contracts-ccip/src/v0.8/ccip/test/mocks/MockARM.sol";
import {IPriceRegistry} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IPriceRegistry.sol";
import {Internal} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Internal.sol";

contract CCIDSenderTest is Test, EVM2EVMOnRampSetup {
    CCIDSender ccidSender;
    HelperSenderConfig helperConfig;
    Router router;
    LinkToken link;
    Operator operator;
    MockARM mockArm;

    address routerAddress;
    address linkAddress;
    address oracle;
    string jobId;
    uint256 oraclePayment;
    string signUpUrl;
    address onRampAddress;
    address mockArmAddress;
    address priceRegistryAddress;

    address public REVEALER = makeAddr("REVEALER");
    address public REVEALEE = makeAddr("REVEALEE");
    uint256 public constant STARTING_USER_BALANCE = 1000 ether;

    address public ccidReceiver = makeAddr("ccidReceiver");
    address public anvilAccount = vm.addr(vm.envUint("ANVIL_PRIVATE_KEY"));
    uint64 ccidDestinationSelector = 16015286601757825753; // Sepolia

    function setUp() public override {
        DeployCCIDSender deployer = new DeployCCIDSender();
        (ccidSender, helperConfig) = deployer.run();
        (routerAddress, linkAddress, oracle, jobId, oraclePayment, signUpUrl,, mockArmAddress) =
            helperConfig.activeNetworkConfig();
        router = Router(routerAddress);
        link = LinkToken(linkAddress);
        operator = Operator(oracle);

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
                destChainSelector: ccidDestinationSelector,
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
            Internal.GasPriceUpdate({destChainSelector: ccidDestinationSelector, usdPerUnitGas: 500000000000000});
        Internal.PriceUpdates memory priceUpdates =
            Internal.PriceUpdates({tokenPriceUpdates: tokenPriceUpdates, gasPriceUpdates: gasPriceUpdates});
        IPriceRegistry(address(s_priceRegistry)).updatePrices(priceUpdates);
    }

    function testConstructorPropertiesSetCorrectly() public {
        assertNotEq(address(ccidSender), address(0));
        assertEq(ccidSender.i_router(), address(router));
        assertEq(ccidSender.i_link(), address(link));
        assertEq(ccidSender.linkAddress(), address(link));
        assertEq(ccidSender.oracleAddress(), address(operator));
        assertEq(ccidSender.jobId(), bytes32(abi.encodePacked(jobId)));
        assertEq(ccidSender.signUpURL(), signUpUrl);
    }

    modifier fundLinkToRevealerAndApprove() {
        vm.startPrank(msg.sender);
        link.transfer(REVEALER, STARTING_USER_BALANCE);
        vm.deal(REVEALER, STARTING_USER_BALANCE);
        vm.stopPrank();
        vm.startPrank(REVEALER);
        link.approve(address(ccidSender), type(uint256).max);
        vm.stopPrank();
        _;
    }

    modifier authorizedSenders() {
        address[] memory authorizedAddresses = new address[](1);
        authorizedAddresses[0] = REVEALER;

        vm.startPrank(0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f);
        operator.setAuthorizedSenders(authorizedAddresses);
        vm.stopPrank();
        _;
    }

    modifier setDestinationSelectorAndReceiverAddress() {
        vm.startPrank(anvilAccount);
        ccidSender.setCcidDestinationSelector(ccidDestinationSelector);
        ccidSender.setCcidReceiver(ccidReceiver);
        vm.stopPrank();
        _;
    }

    modifier applyRampUpdates() {
        vm.startPrank(msg.sender);
        Router.OnRamp memory newOnRamp = Router.OnRamp({
            destChainSelector: 16015286601757825753, // Sepolia
            onRamp: onRampAddress
        });
        Router.OnRamp[] memory newOnRampArray = new Router.OnRamp[](1);
        newOnRampArray[0] = newOnRamp;

        router.applyRampUpdates(newOnRampArray, new Router.OffRamp[](0), new Router.OffRamp[](0));
        vm.stopPrank();
        _;
    }

    modifier fundCcidSenderAndApproveRouter() {
        vm.startPrank(msg.sender);
        link.transfer(address(ccidSender), STARTING_USER_BALANCE);
        vm.stopPrank();
        vm.startPrank(address(ccidSender));
        link.approve(address(router), type(uint256).max);
        link.approve(onRampAddress, type(uint256).max);
        vm.stopPrank();
        _;
    }

    function testFulfillAndSend()
        public
        fundLinkToRevealerAndApprove
        authorizedSenders
        setDestinationSelectorAndReceiverAddress
        applyRampUpdates
        fundCcidSenderAndApproveRouter
    {
        vm.startPrank(REVEALER);
        ccidSender.requestStatus(REVEALEE);
        bytes32 constantRequestId = 0x5e8ebfa50e778e69264bdc847efd6c474992d0ba91772b41eb52d11737a9eafe; // ccidSender.getLatestSentRequestId();
        uint8 kycUserStatus = 1;
        uint40 nonZeroKycTimestamp = 1658845449;
        bytes memory data = abi.encode(constantRequestId, kycUserStatus, nonZeroKycTimestamp);
        operator.fulfillOracleRequest2(
            constantRequestId,
            oraclePayment,
            address(ccidSender),
            bytes4(keccak256("fulfill(bytes32,uint8,uint40)")),
            block.timestamp + 5 minutes,
            data
        );
        vm.stopPrank();
    }

    function testSetCcidReceiver() public {
        vm.startPrank(anvilAccount);
        ccidSender.setCcidReceiver(ccidReceiver);
        assertEq(ccidSender.s_ccidReceiver(), ccidReceiver);
        vm.stopPrank();
    }

    function testSetCcidDestinationSelector() public {
        vm.startPrank(anvilAccount);
        ccidSender.setCcidDestinationSelector(ccidDestinationSelector);
        assertEq(ccidSender.s_ccidDestinationSelector(), ccidDestinationSelector);
        vm.stopPrank();
    }
}
