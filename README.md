# Cross-Chain Identity (CCID)

This project is a prototype for cross-chain identity status verification. Using [Chainlink CCIP](https://docs.chain.link/ccip) and the [Everest Identity Oracle](https://developer.everest.org/#everest-identity-oracle), Cross-Chain Identity (CCID) is a demonstration of how the KYC status of an address can be securely transmitted across chains. Cross-Chain Identity leverages the security and sybil resistance of the underlying protocols to allow a new generation of interoperable and regulatory compliant Web3 applications.

**_Note:_**
_The [Everest Identity Oracle](https://goerli.etherscan.io/address/0xB9756312523826A566e222a34793E414A81c88E1) is currently only available for testing on Ethereum Goerli, which unfortunately is not one of the [test networks available on CCIP](https://docs.chain.link/ccip/supported-networks). Therefore I was unable to deploy and test this project, but the premise remains unchanged._

## Table of Contents

- [Cross-Chain Identity (CCID)](#cross-chain-identity-ccid)
  - [Table of Contents](#table-of-contents)
  - [Versions](#versions)
  - [CCID V1](#ccid-v1)
    - [Overview](#overview)
    - [Usage](#usage)
    - [CCIDSender.sol](#ccidsendersol)
    - [CCIDReceiver.sol](#ccidreceiversol)
    - [Additional Comments on EverestConsumer](#additional-comments-on-everestconsumer)
  - [CCID V2](#ccid-v2)
    - [Overview](#overview-1)
    - [Version Differences](#version-differences)
    - [Usage](#usage-1)
    - [CCIDRequest.sol](#ccidrequestsol)
    - [CCIDFulfill.sol](#ccidfulfillsol)
    - [Additional Comments on Design Choices](#additional-comments-on-design-choices)
  - [Development Resources](#development-resources)
  - [License](#license)

## Versions

There are currently two versions of CCID.

**V1** is the original implementation that builds on the Everest Consumer contract to send fulfilled identity requests from a `CCIDSender` contract to a `CCIDReceiver` contract on another chain.

**V2** is the latest implementation that interacts with the Everest Consumer through an interface and allows bi-directional CCIP transactions between a `CCIDRequest` contract and a `CCIDFulfill` contract.

[Skip to V2 information](#ccid-v2)

## CCID V1

### Overview

`CCIDSender.sol` inherits the functionality from Everest's `EverestConsumer.sol`, and Chainlink's `IRouterClient.sol` and `Client.sol` to send the KYC status of a queried address in the form of a string across chains to `CCIDReceiver.sol` which inherits functionality from `CCIPReceiver.sol` and `Client.sol`.

The three possible results are:

- `NOT_FOUND`
- `HUMAN_AND_UNIQUE`
- `KYC_USER`

These results are determined by an address' association/KYC status with Everest's biometric, [digital identity wallet](https://wallet.everest.org/). Addresses that have been associated with an Everest Wallet and completed KYC will return `KYC_USER`. Addresses that have been associated with an Everest Wallet, but have not completed KYC will return `HUMAN_AND_UNIQUE`. And finally addresses that have not been associated with an Everest Wallet will return `NOT_FOUND`.

### Usage

When this project is able to be deployed, these are the steps that must be followed:

- `CCIDSender.sol` is deployed with the following constructor arguments:
  - `_router` - address of [CCIP Router](https://docs.chain.link/ccip/supported-networks)
  - `_link` - address of Chainlink (LINK) token
  - `_oracle` - address of [Everest Identity Oracle](https://developer.everest.org/#everest-identity-oracle)
  - `_jobId` - string of JobID found in [Everest docs](https://static-assets.everest.org/web/images/HowToSetupAndUseTheEverestChainlinkService.pdf#page=8)
  - `_oraclePayment` - uint256 amount of Chainlink (LINK) to pay
  - `_signUpURL` - string of [Everest Wallet URL](https://wallet.everest.org/)
- send LINK to `CCIDSender` address
- `CCIDReceiver.sol` is deployed to receiving blockchain with the following constructor arguments:
  - `_router` - address of [CCIP Router](https://docs.chain.link/ccip/supported-networks)
- `setCcidReceiver()` is called on first contract, passing address of receiver contract as parameter
- `setCcidDestinationSelector()` is called on first contract, passing [Chain Selector of receiving chain](https://docs.chain.link/ccip/supported-networks) as parameter

Now when a request is made to the EverestConsumer/CCIDSender contract and fulfilled by the oracle, it will send the KYC status of the queried address to the CCIDReceiver contract on the other chain.

### CCIDSender.sol

- imports EverestConsumer, IRouterClient, Client, Ownable
- takes same constructor arguments as EverestConsumer, as well as an address for `router`
- has the following storage variables:
  - address `router`
  - address `link`
  - address `ccidReceiver`
  - uint64 `ccidDestinationSelector`
- has the following setter functions:
  - `setCcidReceiver()` with onlyOwner modifier
  - `setCcidDestinationSelector()` with onlyOwner modifier
- overrides EverestConsumer's `fulfill()` to call `sendKycStatusToCcidReceiver()`
- `sendKycStatusToCcidReceiver()` does the following:
  - takes kyc status of a fulfilled request as parameter
  - converts to string with `statusToString()`
  - sends the status via IRouterClient to CCIDReceiver

### CCIDReceiver.sol

- imports CCIPReceiver and Client
- takes same constructor argument as CCIPReceiver to set `router` address
- overrides `_ccipReceive()` to receive and decode message to get identity status as a string
- emits an event with the received identity status

### Additional Comments on EverestConsumer

This project inherits [my own fork](https://github.com/palmcivet7/hardhat-everest-chainlink-consumer) of the EverestConsumer which changed the visibility of the `statusToString()` function from `external` to `public` to allow CCIDSender to call it. The `fulfill()` was also made `virtual`, and the `_requests` mapping was changed from `private` to `internal`.

## CCID V2

_**V2** is the latest implementation that interacts with the Everest Consumer through an interface and allows bi-directional CCIP transactions between a `CCIDRequest` contract and a `CCIDFulfill` contract._

### Overview

A user interacts only with a `CCIDRequest` contract on their chain of choice to make a request about an address' identity status, which is then sent to a `CCIDFulfill` contract on the chain with the Everest Consumer. `CCIDFulfill` interacts with the Everest Consumer through the `IEverestConsumer` interface and uses Chainlink Log Trigger Automation to monitor fulfilled requests, sending the relevant one back to the `CCIDRequest` contract on the user's chosen chain, all in a single transaction.

### Version Differences

CCID V2 differs from V1 in the following ways:

- interacts with Everest Consumer through an interface, as opposed to importing it directly
- requests can be made from chains the Everest Consumer is not on (bi-directional request functionality)
- additional CCIP "best practices" implemented such as modifiers restricting interactions with unwanted chains
- Identity status is transmitted as an `IEverest.Status` enum, as opposed to a string
- if a user has completed KYC, an epoch timestamp representing their KYC completion date is also transmitted
  - if a user hasn't completed KYC, this value will return 0

### Usage

When this project is able to be deployed, these are the steps that must be followed:

- `CCIDRequest.sol` is deployed on user's chain of choice (_Chain A_) with the following constructor arguments:
  - `_router` - address of [CCIP Router](https://docs.chain.link/ccip/supported-networks)
  - `_link` - address of Chainlink (LINK) token
- `CCIDFulfill.sol` is deployed on same chain as Everest Consumer (_Chain B_) with the following constructor arguments:
  - `_router` - address of [CCIP Router](https://docs.chain.link/ccip/supported-networks)
  - `_link` - address of Chainlink (LINK) token
  - `_consumer` - address of [Everest Consumer](https://static-assets.everest.org/web/images/HowToSetupAndUseTheEverestChainlinkService.pdf#page=8)
  - `_ccidRequest` - address of `CCIDRequest` deployed on Chain A
  - `_chainSelector` - uint64 of [chain selector](https://docs.chain.link/ccip/supported-networks) for Chain A
- `CCIDFulfill` contract owner must call `allowlistSourceChain()` with uint64 of [chain selector](https://docs.chain.link/ccip/supported-networks) for Chain A and true
- `CCIDFulfill` contract owner must call `allowlistSender()` with address of `CCIDRequest` deployed on Chain A and true
- `CCIDRequest` contract owner must call `allowlistDestinationChain()` with uint64 of [chain selector](https://docs.chain.link/ccip/supported-networks) for Chain B and true
- `CCIDRequest` contract owner must call `allowlistSourceChain()` with uint64 of [chain selector](https://docs.chain.link/ccip/supported-networks) for Chain B and true
- `CCIDRequest` contract owner must call `allowlistSender()` with address of `CCIDFulfill` deployed on Chain B and true

Now anyone call call `requestCcidStatus()` with the following parameters:

- address of `CCIDFulfill` on Chain B
- address who's identity status is being requested
- uint64 of [chain selector](https://docs.chain.link/ccip/supported-networks) for Chain B

This will send the request via CCIP to `CCIDFulfill`, which will interact with the Everest Consumer contract to request the identity status of the address. The `requestedAddress` will be stored in an `s_pendingRequests` mapping, evaluating to true. Chainlink's Automation nodes will monitor the Everest Consumer for fulfilled request events using Log Trigger Automation. When one of these events correspond to a true `s_pendingRequests` address, Chainlink Automation will send the `requestedAddress`, `IEverestConsumer.Status` and `kycTimestamp` back to the `CCIDRequest` contract on Chain A. It will also set the `s_pendingRequests` mapping of the `requestedAddress` to false.

This entire process happens in a single transaction.

### CCIDRequest.sol

- imports `IEverestConsumer`, `IRouterClient` and `LinkTokenInterface` interfaces
- imports `Client`, `CCIPReceiver` and Openzeppelin's `Ownable` contracts
- takes CCIP router address and LINK token address as constructor args
  - stores these in immutable variables
- has storage mappings for _allowlisted_ destination chain, source chain, and sender
- `requestCcidStatus()` is used for making requests, taking `_ccidFulfill` address, `_requestedAddress`, and `_chainSelector`
- `_ccipReceive()` receives fulfilled requests, decodes them, and emits a `CCIDStatusReceived` event with `requestedAddress`, `IEverest.Status status`, and `kycTimestamp`
- has the following setter functions with onlyOwner modifier:
  - `allowlistDestinationChain()`
  - `allowlistSourceChain()`
  - `allowlistSender()`

### CCIDFulfill.sol

- imports `IEverestConsumer`, `IRouterClient`, `LinkTokenInterface` and `ILogAutomation` interfaces
- imports `Client`, `CCIPReceiver`, Openzeppelin's `Ownable`, and `AutomationBase` contracts
- imports `Log` struct
- takes CCIP router address, LINK token address, Everest Consumer address, CCIDRequest address, CCIDRequest chain uint64 chain selector as constructor args
  - stores these in immutable variables
- has storage mappings for _allowlisted_ source chain and sender
- has storage mapping for _pendingRequests_ of `requestedAddresses`
- `_ccipReceive()` receives the `requestedAddress` from `CCIDRequest` and:
  - maps the `requestedAddress` to true in `s_pendingRequests`
  - requests the identity status of the `requestedAddress` from the Everest Consumer
  - emits CCIDStatusRequested event with the `requestedAddress`
- `checkLog()` is simulated continuously off chain by Chainlink Automation nodes and:
  - monitors fulfilled request events emitted by the Everest Consumer
  - evaluates `upkeepNeeded` as true when one of these events correspond to a true address mapped in `s_pendingRequests`
  - stores data from fulfilled request events about `requestedAddress` in `performData` which is used to call `performUpkeep()`
- `performUpkeep()` is called by Chainlink Automation nodes when `checkLog()` evaulates `upkeepNeeded` to be true with `performData` and:
  - calls `fulfillCcidRequest()` with `performData`
- `fulfillCcidRequest()` takes `_fulfilledData` (`performData`) and:
  - decodes it, to set the `requestedAddress` `s_pendingRequests` mapping to false and emit a `CCIDStatusFulfilled` event with
  - sends it to `CCIDRequest` via CCIP
- has the following setter functions with onlyOwner modifier:
  - `allowlistSourceChain()`
  - `allowlistSender()`

### Additional Comments on Design Choices

When requests are fulfilled by the Everest Consumer, the address of the "revealer" (the address making the request) is included in the Fulfilled event. Although I added the `kycTimestamp` to V2, unlike V1, I left out the revealer address. This was done because the way the Everest Consumer is built, the revealer address is the msg.sender of the request, which in this case would not be the original user making the request on Chain A - it would be the CCIDFulfill contract.

I also left out the bytes32 `requestId`. Adding this and allowing cross-chain queries of this parameter is something to consider.

The Chainlink Log Trigger Automation needs to be funded with LINK tokens. CCID V2 currently assumes the registration is done manually and tokens are deposited in a subscription. One of the next steps will be making the `requestCcidStatus()` require a payment of LINK tokens that are also sent across chain and used to pay for the use of Log Trigger Automation.

The `IEverestConsumer.Status` enum uses [my pull request version](https://github.com/palmcivet7/everest-chainlink-consumer/blob/master/contracts/interfaces/IEverestConsumer.sol) because the `checkLog()` interprets the enum value as a `uint8` and I believe the order in the original interface is incorrect.

## Development Resources

The following resources were used for developing CCID:

- [CCIP Masterclass docs](https://andrej-rakic.gitbook.io/chainlink-ccip/getting-started/how-to-use-chainlink-ccip)
- [smartcontractkit - ccip-starter-kit-hardhat](https://github.com/smartcontractkit/ccip-starter-kit-hardhat)
- [EverID - everest-chainlink-consumer](https://github.com/EverID/everest-chainlink-consumer)
- [palmcivet7 - hardhat-everest-chainlink-consumer](https://github.com/palmcivet7/hardhat-everest-chainlink-consumer)

## License

This project is licensed under the [MIT License](https://opensource.org/license/mit/).
