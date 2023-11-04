# Cross-Chain Identity (CCID)

This project is a prototype for cross-chain identity status verification. Using [Chainlink CCIP](https://docs.chain.link/ccip) and the [Everest Identity Oracle](https://developer.everest.org/#everest-identity-oracle), Cross-Chain Identity (CCID) is a demonstration of how the KYC status of an address can be securely transmitted across chains. Cross-Chain Identity leverages the security and sybil resistance of the underlying protocols to allow a new generation of interoperable and regulatory compliant Web3 applications.

**_Note:_**
_The [Everest Identity Oracle](https://goerli.etherscan.io/address/0xB9756312523826A566e222a34793E414A81c88E1) is currently only available for testing on Ethereum Goerli, which unfortunately is not one of the [test networks available on CCIP](https://docs.chain.link/ccip/supported-networks). Therefore I was unable to deploy and test this project, but the premise remains unchanged._

## Table of Contents

- [Cross-Chain Identity (CCID)](#cross-chain-identity-ccid)
  - [Table of Contents](#table-of-contents)
  - [Overview](#overview)
  - [Usage](#usage)
  - [CCIDSender.sol](#ccidsendersol)
  - [CCIDReceiver.sol](#ccidreceiversol)
  - [Development Resources](#development-resources)
  - [Additional Comments on EverestConsumer](#additional-comments-on-everestconsumer)
  - [License](#license)

## Overview

`CCIDSender.sol` inherits the functionality from Everest's `EverestConsumer.sol`, and Chainlink's `IRouterClient.sol` and `Client.sol` to send the KYC status of a queried address in the form of a string across chains to `CCIDReceiver.sol` which inherits functionality from `CCIPReceiver.sol`.

The three possible results are:

- `NOT_FOUND`
- `HUMAN_AND_UNIQUE`
- `KYC_USER`

These results are determined by an address' association/KYC status with Everest's biometric, [digital identity wallet](https://wallet.everest.org/). Addresses that have been associated with an Everest Wallet and completed KYC will return `KYC_USER`. Addresses that have been associated with an Everest Wallet, but have not completed KYC will return `HUMAN_AND_UNIQUE`. And finally addresses that have not been associated with an Everest Wallet will return `NOT_FOUND`.

## Usage

When this project is able to be deployed, these are the steps that must be followed:

- `CCIDSender.sol` is deployed with the following constructor arguments:
  - `_router` - address of [CCIP Router](https://docs.chain.link/ccip/supported-networks)
  - `_link` - address of Chainlink (LINK) token
  - `_oracle` - address of [Everest Identity Oracle](https://developer.everest.org/#everest-identity-oracle)
  - `_jobId` - string of JobID found in [Everest docs](https://static-assets.everest.org/web/images/HowToSetupAndUseTheEverestChainlinkService.pdf#page=8)
  - `_oraclePayment` - uint256 amount of Chainlink (LINK) to pay
  - `_signUpURL` - string of [Everest Wallet URL](https://wallet.everest.org/)
- approve spending LINK for `CCIDSender` address
- `CCIDReceiver.sol` is deployed to receiving blockchain with the following constructor arguments:
  - `_router` - address of [CCIP Router](https://docs.chain.link/ccip/supported-networks)
- `setCcidReceiver()` is called on first contract, passing address of receiver contract as parameter
- `setCcidDestinationSelector()` is called on first contract, passing [Chain Selector of receiving chain](https://docs.chain.link/ccip/supported-networks) as parameter

Now when a request is made to the EverestConsumer/CCIDSender contract and fulfilled by the oracle, it will send the KYC status of the queried address to the CCIDReceiver contract on the other chain.

**_Note:_**
_Even though this project is built in Foundry, Chainlink CCIP contracts are installed via npm into node_modules._

## CCIDSender.sol

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

## CCIDReceiver.sol

- imports CCIPReceiver and Client
- takes same constructor argument as CCIPReceiver to set `router` address
- overrides `_ccipReceive()` to receive and decode message to get identity status as a string
- emits an event with the received identity status

## Development Resources

The following resources were used for developing CCID:

- [CCIP Masterclass docs](https://andrej-rakic.gitbook.io/chainlink-ccip/getting-started/how-to-use-chainlink-ccip)
- [smartcontractkit - ccip-starter-kit-hardhat](https://github.com/smartcontractkit/ccip-starter-kit-hardhat)
- [EverID - everest-chainlink-consumer](https://github.com/EverID/everest-chainlink-consumer)
- [palmcivet7 - hardhat-everest-chainlink-consumer](https://github.com/palmcivet7/hardhat-everest-chainlink-consumer)

## Additional Comments on EverestConsumer

This project inherits [my own fork](https://github.com/palmcivet7/hardhat-everest-chainlink-consumer) of the EverestConsumer which changed the visibility of the `fulfill()` and `statusToString()` functions from `external` to `public` to allow CCIDSender to call them. The `fulfill()` was also made `virtual`.

## License

This project is licensed under the [MIT License](https://opensource.org/license/mit/).
