const getAccounts = require("@aragon/os/scripts/helpers/get-accounts");

const BN = require("bn.js");

const globalArtifacts = this.artifacts; // Not injected unless called directly via truffle
const globalWeb3 = this.web3; // Not injected unless called directly via truffle

const defaultOwner = process.env.OWNER;

const bigExp = (x, y = 0) => new BN(x).mul(new BN(10).pow(new BN(y)));
const pct16 = x => bigExp(x, 16);

const ETHER_FAKE_ADDRESS = "0x0000000000000000000000000000000000000000"

module.exports = async (
  truffleExecCallback,
  {
    artifacts = globalArtifacts,
    web3 = globalWeb3,
    owner = defaultOwner,
    verbose = true
  } = {}
) => {
  try {
    const log = (...args) => {
      if (verbose) {
        console.log(...args);
      }
    };

    const DandelionOrg = this.artifacts.require("DandelionOrg");
    const ERC20 = artifacts.require("ERC20Sample");

    log("New Instane...");

    const accounts = await getAccounts(web3);
    if (!owner) {
      owner = accounts[0];
      log(
        "OWNER env variable not found, setting APM owner to the provider's first account"
      );
    }
    log("Owner:", owner);

    const dandelionOrgAdress = process.argv[4]
    const dandelionOrg = await DandelionOrg.at(dandelionOrgAdress)

    // General time units 
    const ONE_HOUR = 60 * 60
    const ONE_WEEK = ONE_HOUR * 24 * 7;
    const ONE_HOUR_BLOCKS = Math.round(ONE_HOUR / 15)
    const ONE_WEEK_BLOCKS = Math.round(ONE_WEEK / 15)

    // Voting settings
    const SUPPORT_REQUIRED = 50e16;
    const MIN_ACCEPTANCE_QUORUM = 5e16;
    const VOTE_DURATION = ONE_WEEK_BLOCKS;
    const VOTE_BUFFER = ONE_HOUR_BLOCKS
    const VOTE_EXECUTION_DELAY = ONE_HOUR_BLOCKS

    const VOTING_SETTINGS = [
      SUPPORT_REQUIRED,
      MIN_ACCEPTANCE_QUORUM,
      VOTE_DURATION,
      VOTE_BUFFER,
      VOTE_EXECUTION_DELAY
    ];

    // Time Lock settings
    const INITIAL_LOCK_AMOUNT = new BN(10);
    const INITIAL_LOCK_DURATION = 60; // seconds
    const INITIAL_SPAM_PENALTY_FACTOR = pct16(50); // 50%
    const TIME_LOCK_SETTINGS = [
      INITIAL_LOCK_DURATION,
      INITIAL_LOCK_AMOUNT,
      INITIAL_SPAM_PENALTY_FACTOR
    ];

    const daoID = `Dandelion${Math.floor(Math.random() * 100)}`;
    const acceptedDepositToken = [ETHER_FAKE_ADDRESS];
    const redeemableTokens = [ETHER_FAKE_ADDRESS];

    const timeLockToken = await ERC20.new(owner, "Lock Token", "LKT", {
      from: owner
    });

    const receipt = await dandelionOrg.installDandelionApps(
      daoID,
      acceptedDepositToken,
      redeemableTokens,
      timeLockToken.address,
      TIME_LOCK_SETTINGS,
      VOTING_SETTINGS,
      { from: owner, gas: 10000000 }
    );

    if (typeof truffleExecCallback === "function") {
      // Called directly via `truffle exec`
      truffleExecCallback();
    } else {
      return {};
    }
  } catch (error) {
    console.log("ERROR : ", error);
  }
};
