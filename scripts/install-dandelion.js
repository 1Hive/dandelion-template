const getAccounts = require('@aragon/os/scripts/helpers/get-accounts')

const BN = require('bn.js')

const globalArtifacts = this.artifacts // Not injected unless called directly via truffle
const globalWeb3 = this.web3 // Not injected unless called directly via truffle

const defaultOwner = process.env.OWNER

module.exports = async (
  truffleExecCallback,
  {
    artifacts = globalArtifacts,
    web3 = globalWeb3,
    owner = defaultOwner,
    verbose = true,
  } = {}
) => {
  const log = (...args) => {
    if (verbose) {
      console.log(...args)
    }
  }

  const DandelionOrg = this.artifacts.require('DandelionOrg')
  const ERC20 = artifacts.require('ERC20Sample')

  log('New Instane...')

  const accounts = await getAccounts(web3)
  if (!owner) {
    owner = accounts[0]
    log(
      "OWNER env variable not found, setting APM owner to the provider's first account"
    )
  }
  log('Owner:', owner)

  const dandelionOrg = await DandelionOrg.at('0x08c18b4e04386f2fa729623d697729f85823882f')

  const ONE_DAY = 60 * 60 * 24
  const ONE_WEEK = ONE_DAY * 7

  const VOTE_DURATION = ONE_WEEK
  const SUPPORT_REQUIRED = 50e16
  const MIN_ACCEPTANCE_QUORUM = 5e16
  const VOTING_SETTINGS = [
    SUPPORT_REQUIRED,
    MIN_ACCEPTANCE_QUORUM,
    VOTE_DURATION,
  ]

  const bigExp = (x, y = 0) => new BN(x).mul(new BN(10).pow(new BN(y)))
  const pct16 = x => bigExp(x, 16)
  const decimals = 18

  const INITIAL_LOCK_AMOUNT = bigExp(10, decimals)
  const INITIAL_LOCK_DURATION = 60 // seconds
  const INITIAL_SPAM_PENALTY_FACTOR = pct16(50) // 50%
  const TIME_LOCK_SETTINGS = [
    INITIAL_LOCK_AMOUNT,
    INITIAL_LOCK_DURATION,
    INITIAL_SPAM_PENALTY_FACTOR,
  ]

  const daoID = 'mycompany'
  const acceptedDepositToken = []

  const timeLockToken = await ERC20.new({ from: owner })

  log('Time Lock Token:', timeLockToken)

  const receipt = await dandelionOrg.installDandelionApps(
    daoID,
    acceptedDepositToken,
    timeLockToken.address,
    TIME_LOCK_SETTINGS,
    VOTING_SETTINGS,
    { from: owner }
  )

  log('Install receipt: ', receipt)

  if (typeof truffleExecCallback === 'function') {
    // Called directly via `truffle exec`
    truffleExecCallback()
  } else {
    return {}
  }
}


