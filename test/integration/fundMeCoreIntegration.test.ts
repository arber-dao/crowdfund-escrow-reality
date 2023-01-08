import { assert, expect } from "chai"
import { network, deployments, ethers } from "hardhat"
import { developmentChains, networkConfig } from "../../helper-hardhat-config"
import { CentralizedArbitrator, ERC20Mock, FundMeCore, NonCompliantERC20Mock } from "../../typechain-types"
import { BigNumber, ContractReceipt, ContractTransaction, Event } from "ethers"
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers"
import { ArbitrableStatus, ArbitrableParty } from "../../utils/types"
import { moveTime } from "../../utils/move-network"
import { readJson } from "../../utils/readJson"
import { ensureBalanceAfterTransaction, getEvidenceGroupId } from "../testHelper"
import {
  ALLOWED_NUMBER_OF_MILESTONES,
  APPEAL_DURATION,
  ARBITRATION_FEE,
  ARBITRATOR_EXTRA_DATA,
  CREATE_TRANSACTION_FEE,
  INFINITESIMAL_VALUE,
  RECEIVER_WITHDRAW_TIMEOUT,
  ZERO_ADDRESS,
} from "../../utils/constants"
import { getProjectRoot } from "../../utils/helpers"
import { testClaimMilestoneData } from "./testData"

!developmentChains.includes(network.name)
  ? describe.skip
  : describe("Fund Me Contract Integration Test Suite", async function () {
      let fundMeContract: FundMeCore,
        centralizedArbitratorContract: CentralizedArbitrator,
        erc20Contract: ERC20Mock,
        deployer: SignerWithAddress,
        receiver: SignerWithAddress,
        funder1: SignerWithAddress,
        funder2: SignerWithAddress,
        funder3: SignerWithAddress

      // const timeoutPayment = 10 /* seconds */
      const metaEvidenceUri = "This is the Meta Evidence!"
      const evidenceUri = "This is my Evidence!"

      beforeEach(async () => {
        ;[deployer, receiver, funder1, funder2, funder3] = await ethers.getSigners()
        await deployments.fixture(["main", "mock"])
        fundMeContract = await ethers.getContract("FundMeCore")
        centralizedArbitratorContract = await ethers.getContract("CentralizedArbitrator")
        erc20Contract = await ethers.getContract("ERC20Mock")
      })

      describe("Full Claim Milestone Integration Tests", async () => {
        let funders: [SignerWithAddress, SignerWithAddress, SignerWithAddress]
        let transactionIds: number[] = []

        beforeEach(async () => {
          funders = [funder1, funder2, funder3]

          for (const transaction in testClaimMilestoneData.transactionsMilestoneAmountUnlockable) {
            const arbitratorExtraData = Array.from(
              { length: testClaimMilestoneData.transactionsMilestoneAmountUnlockable[transaction].length },
              () => ARBITRATOR_EXTRA_DATA
            )

            const createTransactionTx = await fundMeContract
              .connect(receiver)
              .createTransaction(
                testClaimMilestoneData.transactionsMilestoneAmountUnlockable[transaction],
                arbitratorExtraData,
                RECEIVER_WITHDRAW_TIMEOUT,
                erc20Contract.address,
                metaEvidenceUri,
                {
                  value: CREATE_TRANSACTION_FEE,
                }
              )

            const createTransactionReceipt = await createTransactionTx.wait()
            transactionIds.push(createTransactionReceipt.events![1].args!._transactionId)

            for (const funder in funders) {
              const increaseAllowanceTx = await erc20Contract
                .connect(funders[funder])
                .increaseAllowance(
                  fundMeContract.address,
                  testClaimMilestoneData.transactionsFunderAmountFunded[transaction][funder]
                )
              await increaseAllowanceTx.wait()

              const functionTransactionTx = await fundMeContract
                .connect(funders[funder])
                .fundTransaction(
                  transactionIds[transaction],
                  testClaimMilestoneData.transactionsFunderAmountFunded[transaction][funder]
                )
              await functionTransactionTx.wait()
            }
          }
        })

        it("test getMilestoneAmountClaimable() for various transactions with varying amounts for milestoneAmountUnlockable ", async () => {
          // loop across transactions
          for (const transactionId in transactionIds) {
            // loops across milestones within a transaction
            for (const i in testClaimMilestoneData.transactionsMilestoneAmountUnlockable[transactionId]) {
              const milestoneId = Number(i)
              // call requestClaimMilestone
              await expect(
                fundMeContract
                  .connect(receiver)
                  .requestClaimMilestone(transactionIds[transactionId], milestoneId, evidenceUri)
              )
                .to.emit(fundMeContract, "MilestoneProposed")
                .withArgs(transactionIds[transactionId], milestoneId)
                .to.emit(fundMeContract, "Evidence")
                .withArgs(
                  centralizedArbitratorContract.address,
                  getEvidenceGroupId(transactionIds[transactionId], milestoneId).toBigInt(),
                  receiver.address,
                  evidenceUri
                )

              let transactionMilestone = await fundMeContract.getTransactionMilestone(
                transactionIds[transactionId],
                milestoneId
              )

              // check amountClaimable is the expected value +/- a very small value (I think very small value has to be included since javascript
              // cannot calculate decimal places very well)
              assert(
                transactionMilestone.amountClaimable.toBigInt() >
                  testClaimMilestoneData.testWithoutAddedFunds.expectedMilestoneAmountClaimable[transactionId][
                    milestoneId
                  ]
                    .sub(INFINITESIMAL_VALUE)
                    .toBigInt() &&
                  transactionMilestone.amountClaimable.toBigInt() <
                    testClaimMilestoneData.testWithoutAddedFunds.expectedMilestoneAmountClaimable[transactionId][
                      milestoneId
                    ]
                      .add(INFINITESIMAL_VALUE)
                      .toBigInt(),
                `amount claimable for transactionId ${transactionIds[transactionId]}, milestoneId ${milestoneId} does not equal expected value. ` +
                  `Expected: ${testClaimMilestoneData.testWithoutAddedFunds.expectedMilestoneAmountClaimable[
                    transactionId
                  ][milestoneId].toBigInt()}. Actual: ${transactionMilestone.amountClaimable.toBigInt()}`
              )
              // move time
              moveTime(RECEIVER_WITHDRAW_TIMEOUT)
              // call claimMilestone
              await expect(fundMeContract.connect(receiver).claimMilestone(transactionIds[transactionId], milestoneId))
                .to.emit(fundMeContract, "MilestoneResolved")
                .withArgs(transactionIds[transactionId], milestoneId)

              // check balanceCrowdFundToken for receiver and crowdfund token address

              const receiverBalance = await fundMeContract.accountBalance(receiver.address, erc20Contract.address)
              assert(
                receiverBalance.toBigInt() == transactionMilestone.amountClaimable.toBigInt(),
                `receiverBalance for transactionId ${transactionIds[transactionId]}, milestoneId ${milestoneId} does not equal amountClaimable. ` +
                  `receiverBalance: ${receiverBalance.toString()}. amountClaimable: ${transactionMilestone.amountClaimable.toString()}`
              )

              let transaction = await fundMeContract.getTransaction(transactionIds[transactionId])
              transactionMilestone = await fundMeContract.getTransactionMilestone(
                transactionIds[transactionId],
                milestoneId
              )

              // check nextClaimableMilestoneCounter
              assert(
                transaction.nextClaimableMilestoneCounter == milestoneId + 1,
                `nextClaimableMilestoneCounter does not equal expected value. Expected: ${milestoneId + 1}. Actual: ${
                  transaction.nextClaimableMilestoneCounter
                }`
              )

              // check milestone status set to resolved
              assert(
                transactionMilestone.status == ArbitrableStatus.Resolved,
                `milestone status does  notequal expected value. Expected: ${ArbitrableStatus.Resolved}. Actual: ${transactionMilestone.status}`
              )
            }
            // after all milestones have been claimed for a transaction, the final remainingFunds should be 0
            const transaction = await fundMeContract.getTransaction(transactionIds[transactionId])
            assert(
              transaction.remainingFunds.toNumber() == 0,
              `remainingFunds for transactionId ${transactionIds[transactionId]} does not equal expected value. ` +
                `Expected: 0. Actual: ${transaction.remainingFunds.toString()}`
            )
          }
        })

        it("test getMilestoneAmountClaimable() for various transactions with varying amounts for milestoneAmountUnlockable AND additional added funds", async () => {
          // loop across transactions
          for (const transactionId in transactionIds) {
            // loops across milestones within a transaction
            for (const i in testClaimMilestoneData.transactionsMilestoneAmountUnlockable[transactionId]) {
              const milestoneId = Number(i)
              // add more funds

              const increaseAllowanceTx = await erc20Contract
                .connect(funders[0])
                .increaseAllowance(
                  fundMeContract.address,
                  testClaimMilestoneData.testWithAddedFunds.fundsToAddBeforeMilestoneClaim[transactionId][milestoneId]
                )
              await increaseAllowanceTx.wait()

              const functionTransactionTx = await fundMeContract
                .connect(funders[0])
                .fundTransaction(
                  transactionIds[transactionId],
                  testClaimMilestoneData.testWithAddedFunds.fundsToAddBeforeMilestoneClaim[transactionId][milestoneId]
                )
              await functionTransactionTx.wait()

              // call requestClaimMilestone
              await expect(
                fundMeContract
                  .connect(receiver)
                  .requestClaimMilestone(transactionIds[transactionId], milestoneId, evidenceUri)
              )
                .to.emit(fundMeContract, "MilestoneProposed")
                .withArgs(transactionIds[transactionId], milestoneId)
                .to.emit(fundMeContract, "Evidence")
                .withArgs(
                  centralizedArbitratorContract.address,
                  getEvidenceGroupId(transactionIds[transactionId], milestoneId).toBigInt(),
                  receiver.address,
                  evidenceUri
                )

              let transactionMilestone = await fundMeContract.getTransactionMilestone(
                transactionIds[transactionId],
                milestoneId
              )

              // check amountClaimable is the expected value +/- a very small value (I think very small value has to be included since javascript
              // cannot calculate decimal places very well)
              assert(
                transactionMilestone.amountClaimable.toBigInt() >
                  testClaimMilestoneData.testWithAddedFunds.expectedMilestoneAmountClaimable[transactionId][milestoneId]
                    .sub(INFINITESIMAL_VALUE)
                    .toBigInt() &&
                  transactionMilestone.amountClaimable.toBigInt() <
                    testClaimMilestoneData.testWithAddedFunds.expectedMilestoneAmountClaimable[transactionId][
                      milestoneId
                    ]
                      .add(INFINITESIMAL_VALUE)
                      .toBigInt(),
                `amount claimable for transactionId ${transactionIds[transactionId]}, milestoneId ${milestoneId} does not equal expected value. ` +
                  `Expected: ${testClaimMilestoneData.testWithAddedFunds.expectedMilestoneAmountClaimable[
                    transactionId
                  ][milestoneId].toString()}. Actual: ${transactionMilestone.amountClaimable.toString()}`
              )

              // move time
              moveTime(RECEIVER_WITHDRAW_TIMEOUT)
              // call claimMilestone
              await expect(fundMeContract.connect(receiver).claimMilestone(transactionIds[transactionId], milestoneId))
                .to.emit(fundMeContract, "MilestoneResolved")
                .withArgs(transactionIds[transactionId], milestoneId)

              // check balanceCrowdFundToken for receiver and crowdfund token address
              const receiverBalance = await fundMeContract.accountBalance(receiver.address, erc20Contract.address)
              assert(
                receiverBalance.toBigInt() == transactionMilestone.amountClaimable.toBigInt(),
                `receiverBalance for transactionId ${transactionIds[transactionId]}, milestoneId ${milestoneId} does not equal amountClaimable. ` +
                  `receiverBalance: ${receiverBalance.toString()}. amountClaimable: ${transactionMilestone.amountClaimable.toString()}`
              )

              let transaction = await fundMeContract.getTransaction(transactionIds[transactionId])
              transactionMilestone = await fundMeContract.getTransactionMilestone(
                transactionIds[transactionId],
                milestoneId
              )

              // check nextClaimableMilestoneCounter
              assert(
                transaction.nextClaimableMilestoneCounter == milestoneId + 1,
                `nextClaimableMilestoneCounter does not equal expected value. Expected: ${milestoneId + 1}. Actual: ${
                  transaction.nextClaimableMilestoneCounter
                }`
              )

              // check milestone status set to resolved
              assert(
                transactionMilestone.status == ArbitrableStatus.Resolved,
                `milestone status does  notequal expected value. Expected: ${ArbitrableStatus.Resolved}. Actual: ${transactionMilestone.status}`
              )
            }
            // after all milestones have been claimed for a transaction, the final remainingFunds should be 0
            const transaction = await fundMeContract.getTransaction(transactionIds[transactionId])
            assert(
              transaction.remainingFunds.toNumber() == 0,
              `remainingFunds for transactionId ${transactionIds[transactionId]} does not equal expected value. ` +
                `Expected: 0. Actual: ${transaction.remainingFunds.toString()}`
            )
          }
        })
      })
    })
