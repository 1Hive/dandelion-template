const DAOFactory = artifacts.require("DAOFactory")
const EVMScriptRegistryFactory = artifacts.require("EVMScriptRegistryFactory")

module.exports = async callback => {

  try {

    const evmScriptRegistryFactory = await EVMScriptRegistryFactory.new()
    console.log(`Deployed evmScriptRegistrryFactory: ${evmScriptRegistryFactory.address}`)

    const daoFactory = await DAOFactory.new("0xaa1A0367C7588937cbF542EF79cbfE83D317DA88", "0x31573901c03188d89530b84EEe815d6bF1C83a16", evmScriptRegistryFactory.address)
    console.log(`Deployed daoFactory: ${daoFactory.address}`)

  } catch (error) {
    callback(error)
  }
  callback()
}