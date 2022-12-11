import { ethers } from "hardhat"

export const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000"
export const INFINITESIMAL_VALUE = ethers.BigNumber.from(100)

/********************************************/
/***** Centralized Arbitrator ***************/
/********************************************/
export const APPEAL_DURATION = 60 /* seconds */
export const ARBITRATION_FEE = ethers.utils.parseEther("0.1")
export const APPEAL_FEE = ethers.utils.parseEther("0.1")

/********************************************/
/***** FundMe ******/
/********************************************/

export const CREATE_TRANSACTION_FEE = ethers.utils.parseEther("0.1")
export const APPEAL_FEE_TIMEOUT = 10000
export const RECEIVER_WITHDRAW_TIMEOUT = 10000

// Arbitrator extra data. ID of the dispute's subcourt (first 32 bytes), the minimum number of jurors
// required (next 32 bytes) and the ID of the specific dispute kit (last 32 bytes)
export const ARBITRATOR_EXTRA_DATA = "0x"

// time at which dispute will timeout if one of the parties does not pay arbitration fee. At this time
// the other party can claim the locked funds
export const ARBITRATION_FEE_TIMEOUT = 60 /* seconds */

// no more than the specified amount of milestones can be created
export const ALLOWED_NUMBER_OF_MILESTONES = 20

// the amount of eth required to be sent to the function createTransaction in FundMe.sol contract
export const CREATE_TRANSACTION_COST = ethers.utils.parseEther("0.1")

/********************************************/
/***** ERC20 Mock ***************************/
/********************************************/

export const ERC20_MOCK_TOTAL_SUPPLY = ethers.utils.parseEther("10000000000")
export const FUNDER_1_ERC20_BALANCE = ethers.utils.parseEther("10000000")
export const FUNDER_2_ERC20_BALANCE = ethers.utils.parseEther("20000000")
export const FUNDER_3_ERC20_BALANCE = ethers.utils.parseEther("30000000")
