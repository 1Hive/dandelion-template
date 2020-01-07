const ACL = artifacts.require('./ACL.sol')

module.exports = function (deployer) {
  deployer.deploy(ACL)
}