import { ethers } from "hardhat"

export const testClaimMilestoneData = {
  // must be BigNumber[4][] - [4] corresponds to number of transaction - [] corresponds to number of milestones
  // represents % claimable per milestone, all milestones in a transaction must total 1 ether == 100%
  transactionsMilestoneAmountUnlockable: [
    [ethers.utils.parseEther("0.2"), ethers.utils.parseEther("0.4"), ethers.utils.parseEther("0.4")],
    [
      ethers.utils.parseEther("0.3"),
      ethers.utils.parseEther("0.3"),
      ethers.utils.parseEther("0.15"),
      ethers.utils.parseEther("0.25"),
    ],
    [ethers.utils.parseEther("0.1"), ethers.utils.parseEther("0.1"), ethers.utils.parseEther("0.8")],
    [
      ethers.utils.parseEther("0.25"),
      ethers.utils.parseEther("0.25"),
      ethers.utils.parseEther("0.25"),
      ethers.utils.parseEther("0.25"),
    ],
  ],
  // must be BigNumber[4][3] - [4] corresponds to number of transaction - 3 corresponds to number of funders
  // represents amount funded for a given transaction
  transactionsFunderAmountFunded: [
    [ethers.utils.parseEther("10"), ethers.utils.parseEther("20"), ethers.utils.parseEther("30")], //total = 60
    [ethers.utils.parseEther("30"), ethers.utils.parseEther("10"), ethers.utils.parseEther("100")], //total = 140
    [ethers.utils.parseEther("20"), ethers.utils.parseEther("20"), ethers.utils.parseEther("10")], //total = 50
    [ethers.utils.parseEther("70"), ethers.utils.parseEther("10"), ethers.utils.parseEther("90")], //total = 170
  ],

  testWithoutAddedFunds: {
    // expectedMilestoneAmountClaimable calculated by hand. simply:
    // [milestoneAmountUnlockable {as a fraction} * {transaction} totalFunded] {for each milestone}
    // must be BigNumber[4][] - [4] corresponds to number of transaction - [] corresponds to number of milestones
    expectedMilestoneAmountClaimable: [
      [ethers.utils.parseEther("12"), ethers.utils.parseEther("24"), ethers.utils.parseEther("24")],
      [
        ethers.utils.parseEther("42"),
        ethers.utils.parseEther("42"),
        ethers.utils.parseEther("21"),
        ethers.utils.parseEther("35"),
      ],
      [ethers.utils.parseEther("5"), ethers.utils.parseEther("5"), ethers.utils.parseEther("40")],
      [
        ethers.utils.parseEther("42.5"),
        ethers.utils.parseEther("42.5"),
        ethers.utils.parseEther("42.5"),
        ethers.utils.parseEther("42.5"),
      ],
    ],
  },

  testWithAddedFunds: {
    // expectedMilestoneAmountClaimable calculated by hand. when funders add funds in between milestone claims, the calculation is more complicated:
    // [(milestoneAmountUnlockable {as a fraction} / (sum([remainingMilestoneAmountUnlockable {as fractions}]))) * {transaction} remainingFunds] {for each milestone}
    // where remainingFunds is the funds that are left in the transaction after milestones have been claimed
    // must be BigNumber[4][] - [4] corresponds to number of transaction - [] corresponds to number of milestones
    expectedMilestoneAmountClaimable: [
      [ethers.utils.parseEther("14"), ethers.utils.parseEther("35.5"), ethers.utils.parseEther("45.5")], //total 95 ✅
      [
        ethers.utils.parseEther("48"),
        ethers.utils.parseEther("396").div(7),
        ethers.utils.parseEther("1107").div(28),
        ethers.utils.parseEther("2405").div(28),
      ], //total 230 ✅
      [ethers.utils.parseEther("5.5"), ethers.utils.parseEther("5.5"), ethers.utils.parseEther("64")], //total 75 ✅
      [
        ethers.utils.parseEther("47.5"),
        ethers.utils.parseEther("305").div(6),
        ethers.utils.parseEther("395").div(6),
        ethers.utils.parseEther("485").div(6),
      ], //total 245 ✅
    ],
    // represents funds to be added by a funder before each milestone is claimed. this with test whether or not FundMeCore properly calculates
    // milestone amountClaimable when funds are added to a transaction in between milestone claims
    // must be BigNumber[4][] - [4] corresponds to number of transaction - [] corresponds to number of milestones
    fundsToAddBeforeMilestoneClaim: [
      [ethers.utils.parseEther("10"), ethers.utils.parseEther("15"), ethers.utils.parseEther("10")],
      [
        ethers.utils.parseEther("20"),
        ethers.utils.parseEther("20"),
        ethers.utils.parseEther("30"),
        ethers.utils.parseEther("20"),
      ],
      [ethers.utils.parseEther("5"), ethers.utils.parseEther("0"), ethers.utils.parseEther("20")],
      [
        ethers.utils.parseEther("20"),
        ethers.utils.parseEther("10"),
        ethers.utils.parseEther("30"),
        ethers.utils.parseEther("15"),
      ],
    ],
  },
}
