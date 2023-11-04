// Custom type imports may vary based on your actual codebase
import { ethers } from "ethers";
import { expect } from "chai";
import { constants } from "@openzeppelin/test-helpers";
import { oracle } from "@chainlink/test-helpers";
import Web3 from "web3";

// Suppress "Duplicate definition of" warnings caused by ethers v5
const customLog = (msg: string) => {
  if (/Duplicate definition of/.test(msg)) {
    return;
  }
  console.log(msg);
};
console.log = customLog;

const web3 = new Web3();

describe("EverestConsumer", function () {
  let owner: ethers.Signer,
    stranger: ethers.Signer,
    revealer: ethers.Signer,
    revealee: ethers.Signer,
    node: ethers.Signer,
    randomAddress: ethers.Signer;
  const jobId = "509e8dd8de054d3f918640ab0a2b77d8";
  const oraclePayment = "1000000000000000000"; // 10 ** 18
  const defaultSignUpURL = "https://everest.org";

  beforeEach(async function () {
    [owner, stranger, revealer, revealee, node, randomAddress] =
      await ethers.getSigners();

    const LinkTokenFactory = await ethers.getContractFactory("LinkToken");
    this.link = await LinkTokenFactory.connect(owner).deploy();

    const OracleFactory = await ethers.getContractFactory("Operator");
    this.oracle = await OracleFactory.connect(owner).deploy(
      this.link.address,
      owner.address
    );

    const EverestConsumerFactory = await ethers.getContractFactory(
      "EverestConsumer"
    );
    this.consumer = await EverestConsumerFactory.connect(owner).deploy(
      this.link.address,
      this.oracle.address,
      jobId,
      oraclePayment,
      defaultSignUpURL
    );
  });

  // ... (the rest of your code remains mostly the same)
});
