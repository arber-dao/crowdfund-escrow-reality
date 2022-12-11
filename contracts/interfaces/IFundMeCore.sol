// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../interfaces/IArbitrable.sol";
import "../interfaces/IEvidence.sol";
import "../interfaces/IArbitrator.sol";
import "../interfaces/IFundMeErrors.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/** @title FundMe
 *  A contract storing ERC20 tokens raised in a crowdfunding event.
 */
interface IFundMeCore is IArbitrable, IEvidence, IFundMeErrors {
  /**************************************/
  /**** Types ***************************/
  /**************************************/

  struct Constants {
    IArbitrator arbitrator; // The address of the arbitrator
    address governor; // The address of the governor contract
    uint16 allowedNumberOfMilestones; // The allowed number of milestones in a transaction. NOTE MAX = 2^16 - 1 = 65535
    uint128 createTransactionCost; // the amount of eth to send when calling createTransaction. NOTE MAX = 2^128 - 1 = 3.4*10^20 ether
    uint64 appealFeeTimeout; /* Time in seconds a party can take to pay arbitration fees before being considered unresponsive at which point they lose 
                              the dispute. set by the governors. NOTE MAX = 2^64 - 1 seconds = 5.8*10^11 years. Safe */
  }

  /** @notice the current status of a milestone
   *  @param Created The milestone has been created
   *  @param Claiming The milestone has had a request to be claimed by the receiver. The milestone 
             can be disputed by the funders for the next receiverWithdrawTimeout seconds
   *  @param WaitingReceiver A request to dispute has been submitted by the funders. Currently
   *         waiting for the receiver to pay arbitration fee so dispute can be created
   *  @param DisputeCreated receiver has submitted arbitration fee, and a dispute has been forwarded
             to the kleros court for ruling
   *  @param Resolved milestone is complete, any disputes are resolved, and the milestone funds have 
             been transfered into the balance of the receiver
   */
  enum Status {
    Created,
    Claiming,
    DisputeCreated,
    Resolved
  }

  enum DisputeChoices {
    None,
    FunderWins,
    ReceiverWins
  }

  struct DisputeStruct {
    uint32 transactionId; // ID of the transaction
    uint16 milestoneId; // ID of the milestone
    bool isRuled; // Whether the dispute has been ruled or not.
    DisputeChoices ruling; // Ruling given by the arbitrator. corresponds to one of enum DisputeChoices
  }

  struct Milestone {
    uint64 amountUnlockablePercentage; /* The amount as a percentage which can be unlocked for this milestone (value for each milestone 
            is measured between 0 and 1 ether ie. 0.2 ether corresponds to 20%). NOTE uint64 is safe since amountUnlockablePercentage cannot exceed
            1 ether and uint64 allows up to 18 ether  */
    uint256 amountClaimable; /* The amount claimable which is declared when receiver wants to claim a milestone. NOTE should be kept as uint256 incase 
            crowdfundToken has a very large supply */
    bytes arbitratorExtraData; /* Additional info about the dispute. We use it to pass the ID of the dispute's subcourt (first 32 bytes),
                                the minimum number of jurors required (next 32 bytes) and the ID of the specific dispute kit (last 32 bytes). */
    Status status; // the dispute status for a milestone. TODO IMPLEMENTATION QUESTION: 1! Should disputes occur at the milestone level
  }

  struct Timer {
    uint64 receiverWithdrawTimeout; /* A time in seconds set in the transaction for the length of time that funders have to dispute a milestone. If this 
            time is exceeded, and there are no disputes, then the receiver may withdraw the according amount of funds for this milestone */
    uint64 lastInteraction; /* A reference point used for the former 2 timeouts for calculating whether appealFeeTimeout or receiverWithdrawTimeout time 
            has passed. This value will be set to block.timestamp in payDisputeFeeByFunders, requestClaimMilestone functions. */
  }

  struct TransactionFunderDetails {
    uint256 amountFunded; // The total amount that has been funded to a transaction for a given address, denominated in the specified erc20 token
    uint32 latestRefundedDisputeId; // the dispute ids for which the funder has been refunded
  }

  struct TransactionFunds {
    uint256 totalFunded; // Total amount funded denominated in the given crowdfundToken
    uint256 remainingFunds; // Total amount of remaining funds in the transaction after milestones have been finalized. denominated in the given crowdfundToken
  }

  struct Transaction {
    address receiver; // the address that will be paid in the case of completing a milestone
    TransactionFunds transactionFunds;
    uint16 nextClaimableMilestoneCounter; // a counter used to track the next milestone which can be claimed. NOTE MAX = 2^16 - 1 = 65535
    Timer timing;
    Milestone[] milestones; // All the milestones to be completed for this crowdfunding event
    IERC20 crowdfundToken; // Token used for the crowdfunding event. The receiver will be paid in this token
    uint128 paidDisputeFees; // Arbitration fee paid by all funders denominated in ETH for the current milestone. NOTE MAX = 2^128 - 1 = 3.4*10^20 ether
    uint32[] refundableDisputeIds; // tracks the dispute id for everytime funders win a dispute
  }

  /**************************************/
  /**** Events **************************/
  /**************************************/

  /** @notice Emitted when a transaction is created.
   *  @param _transactionId The ID of the transaction.
   *  @param _receiver The address of the receiver. (creator of the transaction)
   *  @param _crowdFundToken the token address used for this crowdfunding event (transaction)
   */
  event TransactionCreated(uint32 indexed _transactionId, address indexed _receiver, address indexed _crowdFundToken);

  /** @notice Emitted when a transaction is funded.
   *  @param _transactionId The ID of the transaction.
   *  @param _sender the address that sent funds to _transactionId
   *  @param _amountFunded The amount funded to the transaction
   */
  event FundTransaction(uint32 indexed _transactionId, address indexed _sender, uint256 _amountFunded);

  /** @notice Emitted when there is an update to an accounts balance
   *  @param _account the address of the EOA/contract
   *  @param _token the address of the token the account is to be paid back in
   *  @param _balance the balance for the given token
   */
  event BalanceUpdate(address indexed _account, address indexed _token, uint256 _balance);

  /** @notice Emitted when a milestone completion is requested by receiver. This milestone can be disputed for time specified by 
              receiverWithdrawTimeout. 
   *  @param _transactionId The ID of the transaction.
   *  @param _milestoneId The ID of the milestone
   */
  event MilestoneProposed(uint32 indexed _transactionId, uint16 indexed _milestoneId);

  /** @notice Emitted when a milestone is resolved. At this point a specific amount of the crowdfund token has been placed into 
              the balance of the receiver. The receiver can now call withdraw to withdraw the funds to their address 
   *  @param _transactionId The ID of the transaction.
   *  @param _milestoneId The ID of the milestone
   */
  event MilestoneResolved(uint32 indexed _transactionId, uint16 indexed _milestoneId);

  /** @notice Emitted when a dispute needs more funds
   *  @param _transactionId The ID of the transaction.
   *  @param _milestoneId The ID of the milestone
   *  @param _contributor address of contributor
   *  @param _amountContributed amount contributed by _contributor
   *  @param _amountRequired amount required to pay for dispute
   *  @param _amountPaid amount total paid towards raising dispute
   */
  event DisputeContribution(
    uint32 indexed _transactionId,
    uint16 indexed _milestoneId,
    address indexed _contributor,
    uint128 _amountContributed,
    uint128 _amountRequired,
    uint128 _amountPaid
  );

  /**************************************/
  /**** Only Governor *******************/
  /**************************************/

  /** @notice change the allowed number of milestones only callable by the contract governor
   *  @param _allowedNumberOfMilestones the updated number of milestones allowed to be created
   */
  function changeAllowedNumberOfMilestones(uint16 _allowedNumberOfMilestones) external;

  /** @notice change the cost to create a transaction only callable by the contract governor
   *  @param _createTransactionCost the updated cost in order to create a transaction
   */
  function changeCreateTransactionCost(uint128 _createTransactionCost) external;

  /**************************************/
  /**** Only Transaction Receiver *******/
  /**************************************/

  /** @notice change the receiver address for a given transaction only callable by transaction receiver
   *  @param _transactionId ID of the transaction.
   *  @param _newTransactionReceiver the address of the new transaction receiver
   */
  function changeTransactionReceiver(uint32 _transactionId, address _newTransactionReceiver) external;

  /**************************************/
  /**** Only Funders ********************/
  /**************************************/

  /**************************************/
  /**** Core Transactions ***************/
  /**************************************/

  /** @notice Create a transaction.
   *  @param _milestoneAmountUnlockablePercentage an array of the % withdrawable from each milestone denominated by 1 ether (see struct Milestone {amountUnlockable})
   *  @param _milestoneArbitratorExtraData the milestone arbitratorExtraData to be used (see Milestone.arbitratorExtraData)
   *  @param _receiverWithdrawTimeout amount of time funders have to dispute a milestone
   *  @param _crowdfundToken The erc20 token to be used in the crowdfunding event
   *  @param _metaEvidenceUri Link to the meta-evidence
   *  @return transactionId The index of the transaction.
   */
  function createTransaction(
    uint64[] memory _milestoneAmountUnlockablePercentage,
    bytes[] memory _milestoneArbitratorExtraData,
    uint64 _receiverWithdrawTimeout,
    address _crowdfundToken,
    string memory _metaEvidenceUri
  ) external payable returns (uint32 transactionId);

  /** @notice declare a ruling only callable by the arbitrator
   *  @param _disputeId the dispute ID
   *  @param _ruling the ruling declarded by the arbitrator
   */
  function rule(uint256 _disputeId, uint256 _ruling) external override(IArbitrable);

  /** @notice Give funds to a transaction
   *  @param _transactionId the ID of the transaction
   *  @param _amountFunded amount to fund to transactionId of the corresponding transactions crowdfundToken
   */
  function fundTransaction(uint32 _transactionId, uint256 _amountFunded) external;

  /** @notice Request to claim a milestone, can only be called by the transaction receiver. at this point, the receiver must submit
              evidence they have completed the milestone. funders can submit a dispute until receiverWithdrawTimeout passes.
   *  @param _transactionId The ID of the transaction to claim funds from
   */
  function requestClaimMilestone(uint32 _transactionId, string memory _evidenceUri) external;

  /** @notice Claim a milestone. if receiverWithdrawTimeout has passed, anyone can call this function to transfer the milestone funds
              the milestone funds into the balance of the receiver.
   *  @param _transactionId The ID of the transaction to claim funds from
   */
  function claimMilestone(uint32 _transactionId) external;

  /** @notice Pay fee to dispute a milestone. To be called by parties claiming the milestone was not completed.
   *  The first party to pay the fee entirely will be reimbursed if the dispute is won.
   *  @param _transactionId The transaction ID
   */
  function createDispute(uint32 _transactionId) external payable;

  /** @notice withdraw funds that are owed to you. Most commonly used by receivers to claim milestone funds, and to withdraw eth funds
   *  @param tokenAddress tokenAddress to withdraw funds for. NOTE set to 0 address to withdraw eth
   */
  function withdraw(address tokenAddress) external;

  /** @notice refund erc20 tokens that should be refunded from funders winning a dispute case on a milestone. NOTE the funder still has to call
   * withdraw() to withdraw the funds
   *  @param _transactionId the transactionId to refund for
   */
  function refund(uint32 _transactionId) external;
}
