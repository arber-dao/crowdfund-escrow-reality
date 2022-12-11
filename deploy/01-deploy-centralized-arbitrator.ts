import { HardhatRuntimeEnvironment } from "hardhat/types"
import { DeployFunction } from "hardhat-deploy/types"
import { network, ethers } from "hardhat"
import { networkConfig } from "../helper-hardhat-config"
import { developmentChains } from "../helper-hardhat-config"
import { verify } from "../utils/verify"
import { APPEAL_DURATION, ARBITRATION_FEE, APPEAL_FEE } from "../utils/constants"

const deployArbitrator: DeployFunction = async (hre: HardhatRuntimeEnvironment) => {
  const { getNamedAccounts, deployments, network } = hre
  const { deploy, log } = deployments
  const { deployer } = await getNamedAccounts()

  log("----------------------------------------------------")
  let args: any[] = [ARBITRATION_FEE, APPEAL_DURATION, APPEAL_FEE]
  const arbitratorContract = await deploy("CentralizedArbitrator", {
    from: deployer,
    args: args,
    log: true,
    waitConfirmations: networkConfig[network.name].blockConfirmations || 1,
  })

  // Verify the deployment
  if (!developmentChains.includes(network.name) && process.env.ETHERSCAN_API_KEY) {
    log("Verifying...")
    await verify(arbitratorContract.address, args)
  }
}

export default deployArbitrator
deployArbitrator.tags = ["all", "main", "arbitrator"]
