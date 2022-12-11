import { HardhatRuntimeEnvironment } from "hardhat/types"
import { DeployFunction } from "hardhat-deploy/types"
import { network, ethers } from "hardhat"
import { networkConfig } from "../../helper-hardhat-config"
import { developmentChains } from "../../helper-hardhat-config"
import { verify } from "../../utils/verify"
import {
  ERC20_MOCK_TOTAL_SUPPLY,
  FUNDER_1_ERC20_BALANCE,
  FUNDER_2_ERC20_BALANCE,
  FUNDER_3_ERC20_BALANCE,
} from "../../utils/constants"

const deployErc20Mock: DeployFunction = async (hre: HardhatRuntimeEnvironment) => {
  const { deployments } = hre
  const { log } = deployments

  const [deployer, , funder1, funder2, funder3] = await ethers.getSigners()
  const erc20Contract = await ethers.getContract("ERC20Mock")

  log("----------------------------------------------------")

  const transferTx1 = await erc20Contract
    .connect(deployer)
    .transfer(funder1.address, FUNDER_1_ERC20_BALANCE)
  await transferTx1.wait(1)

  const transferTx2 = await erc20Contract
    .connect(deployer)
    .transfer(funder2.address, FUNDER_2_ERC20_BALANCE)
  await transferTx2.wait(1)

  const transferTx3 = await erc20Contract
    .connect(deployer)
    .transfer(funder3.address, FUNDER_3_ERC20_BALANCE)
  await transferTx3.wait(1)
}

export default deployErc20Mock
deployErc20Mock.tags = ["all", "mock", "erc20"]
