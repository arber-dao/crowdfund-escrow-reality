import { network, ethers } from "hardhat"
import { Signer } from "ethers"

export const signProject = async (signer: Signer, message: string): Promise<string> => {
  message = "We are learning about developing application for Web3 together!"
  let signature = await signer.signMessage(message)

  return signature
}
