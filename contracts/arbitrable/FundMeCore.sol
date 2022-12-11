// SPDX-License-Identifier: MIT

/**
 *  @authors: [@ljrahn]
 *  @reviewers: []
 *  @auditors: []
 *  @bounties: []
 *  @deployments: []
 */

pragma solidity 0.8.13;

import "../interfaces/IFundMeCore.sol";
import "../libs/Arrays64.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "hardhat/console.sol";

/** @title FundMeCore
 *  A contract storing ERC20 tokens raised in a crowdfunding event.
 */
contract FundMeCore is IFundMeCore, Ownable, ReentrancyGuard, ERC165 {
  // Lib for arrays
  using Arrays64 for uint64[];

  /**************************************/
  /**** State ***************************/
  /**************************************/

  /**** Constants ***********************/
  Constants public constants;

  /**** Amount Payable ***************/

  // balance of an erc20 token to be paid from this contract. NOTE that in order to keep track of the tokens to be paid to an address, an indexer like
  // thegraph will be very useful for this
  // account address => erc20 contract address --> returns balance of erc20 token to be paid to account address
  // NOTE that if the address for the second mapping (erc20 contract address) is the 0 address, that indicates the native token balance (ETH)
  mapping(address => mapping(address => uint256)) public accountBalance;

  /**** Transaction State ***************/
  uint32 public transactionIdCounter;
  mapping(uint32 => Transaction) private transactions; // mapping of all of the transactions

  // transactionId => funders address --> returns TransactionFunderDetails
  mapping(uint32 => mapping(address => TransactionFunderDetails)) public transactionFunderDetails;

  /**** Dispute State ******************/
  uint32 public localDisputeIdCounter;
  mapping(uint32 => DisputeStruct) public disputes;
  mapping(uint256 => uint32) public externalDisputeIdToLocalDisputeId; // Maps external (arbitrator side) dispute IDs to local dispute IDs.

  /**** Milestone State ****************/

  /** @dev Constructor. Choose the arbitrator.
   *  @param _arbitrator The arbitrator of the contract.
   *  @param _allowedNumberOfMilestones maximum number of allowed milestones included in a transaction
   *  @param _createTransactionCost cost of creating a transaction
   *  @param _appealFeeTimeout amount of time given to provide appeal fee before dispute closes and apposing side wins
   */
  constructor(
    address _arbitrator,
    uint16 _allowedNumberOfMilestones,
    uint128 _createTransactionCost,
    uint64 _appealFeeTimeout
  ) {
    transactionIdCounter = 0;
    localDisputeIdCounter = 0;
    constants.arbitrator = IArbitrator(_arbitrator);
    constants.allowedNumberOfMilestones = _allowedNumberOfMilestones;
    constants.createTransactionCost = _createTransactionCost;
    constants.appealFeeTimeout = _appealFeeTimeout;

    // placeholder transaction to fill the 0 spot
    createTransaction(
      new uint64[](1 ether),
      new bytes[](0x0),
      type(uint64).max,
      0x000000000000000000000000000000000000dEaD,
      "dEaD"
    );
    // placeholder dispute to fill the 0 spot
    disputes[localDisputeIdCounter] = DisputeStruct({
      transactionId: 0,
      milestoneId: 0,
      isRuled: false,
      ruling: DisputeChoices(0)
    });
    localDisputeIdCounter += 1;
  }

  /**************************************/
  /**** Modifiers ***********************/
  /**************************************/

  /** @notice only the owner of the transaction can execute
   *  @param _transactionId ID of the transaction.
   */
  modifier onlyTransactionReceiver(uint32 _transactionId) {
    if (transactions[_transactionId].receiver != msg.sender) {
      revert FundMe__OnlyTransactionReceiver({receiver: transactions[_transactionId].receiver});
    }
    _;
  }

  /** @notice can only execute function if the transaction exists
   *  @param _transactionId ID of the transaction.
   */
  modifier transactionExists(uint32 _transactionId) {
    // receiver address cannot be zero address, therefore the transaction does not exist if the receiver address is the 0 address
    if (transactions[_transactionId].receiver == address(0)) {
      revert FundMe__TransactionNotFound(_transactionId);
    }
    _;
  }

  /**************************************/
  /**** Only Governor *******************/
  /**************************************/

  /// @notice See {IFundMeCore}
  function changeAllowedNumberOfMilestones(uint16 _allowedNumberOfMilestones) external override(IFundMeCore) onlyOwner {
    constants.allowedNumberOfMilestones = _allowedNumberOfMilestones;
  }

  /// @notice See {IFundMeCore}
  function changeCreateTransactionCost(uint128 _createTransactionCost) external override(IFundMeCore) onlyOwner {
    constants.createTransactionCost = _createTransactionCost;
  }

  /**************************************/
  /**** Only Transaction Receiver *******/
  /**************************************/

  /// @notice See {IFundMeCore}
  function changeTransactionReceiver(uint32 _transactionId, address _newTransactionReceiver)
    external
    override(IFundMeCore)
    onlyTransactionReceiver(_transactionId)
  {
    if (_newTransactionReceiver == address(0)) {
      revert FundMe__ZeroAddressInvalid();
    }
    if (_newTransactionReceiver == address(this)) {
      revert FundMe__FundMeContractAddressInvalid();
    }
    transactions[_transactionId].receiver = _newTransactionReceiver;
  }

  /**************************************/
  /**** Only Funders ********************/
  /**************************************/

  /**************************************/
  /**** Core Transactions ***************/
  /**************************************/

  /// @notice See {IFundMeCore}
  function createTransaction(
    uint64[] memory _milestoneAmountUnlockablePercentage,
    bytes[] memory _milestoneArbitratorExtraData,
    uint64 _receiverWithdrawTimeout,
    address _crowdfundToken,
    string memory _metaEvidenceUri
  ) public payable override(IFundMeCore) returns (uint32 transactionId) {
    if (msg.value < constants.createTransactionCost) {
      revert FundMe__PaymentTooSmall({amountRequired: constants.createTransactionCost, amountSent: uint128(msg.value)});
    }
    // milestone length must be less than the allowed number of milestones
    if (
      _milestoneAmountUnlockablePercentage.length > constants.allowedNumberOfMilestones &&
      _milestoneAmountUnlockablePercentage.length > 0
    ) {
      revert FundMe__IncorrectNumberOfMilestoneInitilized({min: 1, max: constants.allowedNumberOfMilestones});
    }
    if (_milestoneAmountUnlockablePercentage.getSum() != 1 ether) {
      revert FundMe__MilestoneAmountUnlockablePercentageNot1();
    }

    if (_milestoneAmountUnlockablePercentage.length != _milestoneArbitratorExtraData.length) {
      revert FundMe__MilestoneDataMismatch();
    }

    // check if the crowdfundToken is an erc20 compliant contract. NOTE that most erc20 contracts will not
    // have ERC165 standard implemented in them so its not possible to check using supportsInterface
    try IERC20(_crowdfundToken).totalSupply() {} catch {
      revert FundMe__NonCompliantERC20(_crowdfundToken);
    }

    transactionId = transactionIdCounter;
    Transaction storage _transaction = transactions[transactionId];

    _transaction.receiver = msg.sender;
    _transaction.timing.receiverWithdrawTimeout = _receiverWithdrawTimeout;
    _transaction.crowdfundToken = IERC20(_crowdfundToken);

    for (uint16 i = 0; i < _milestoneAmountUnlockablePercentage.length; i++) {
      Milestone[] storage _milestones = _transaction.milestones;
      _milestones.push(
        Milestone({
          amountUnlockablePercentage: _milestoneAmountUnlockablePercentage[i],
          arbitratorExtraData: _milestoneArbitratorExtraData[i],
          amountClaimable: 0,
          status: Status.Created
        })
      );
    }

    transactionIdCounter++;

    emit MetaEvidence(transactionId, _metaEvidenceUri); // transactionId == MetaEvidenceId
    emit TransactionCreated(transactionId, msg.sender, _crowdfundToken);
  }

  /// @notice See {IFundMeCore}
  // TODO needs testing!
  function fundTransaction(uint32 _transactionId, uint256 _amountFunded)
    public
    override(IFundMeCore)
    nonReentrant
    transactionExists(_transactionId)
  {
    Transaction storage _transaction = transactions[_transactionId];

    // covers edge case where funder has never funded this disputed transaction
    hasFunderNeverFundedDisputedTransaction(_transactionId);

    if (!isFunderRefunded(_transactionId)) {
      revert FundMe__NotRefundedForDispute({
        latestDisputeId: _transaction.refundableDisputeIds[_transaction.refundableDisputeIds.length - 1]
      });
    }

    _transaction.crowdfundToken.transferFrom(msg.sender, address(this), _amountFunded);

    _transaction.transactionFunds.totalFunded += _amountFunded;
    _transaction.transactionFunds.remainingFunds += _amountFunded;
    transactionFunderDetails[_transactionId][msg.sender].amountFunded += _amountFunded;

    emit FundTransaction(_transactionId, msg.sender, _amountFunded);
  }

  /// @notice See {IFundMeCore} TODO Needs testing
  function requestClaimMilestone(uint32 _transactionId, string memory _evidenceUri)
    public
    override(IFundMeCore)
    nonReentrant
    transactionExists(_transactionId)
    onlyTransactionReceiver(_transactionId)
  {
    Transaction storage _transaction = transactions[_transactionId];
    uint16 _milestoneId = _transaction.nextClaimableMilestoneCounter;
    Milestone storage _milestone = _transaction.milestones[_milestoneId];

    if (_milestone.status != Status.Created) {
      revert FundMe__MilestoneStatusNotCreated(_transactionId, _milestoneId);
    }

    _transaction.timing.lastInteraction = uint64(block.timestamp);
    _milestone.status = Status.Claiming;

    // since funders can keep funding a transaction after milestones have been claimed, a milestones amountClaimable should
    // depend on the remaining milestones amountUnlockable. Therefore we need to adjust the % claimable such that the REMAINING
    // milestones amountUnlockablePercentage total to 100% (1 ether), then we can calculate the amountClaimable
    _milestone.amountClaimable = getMilestoneAmountClaimable(_transactionId);

    emit MilestoneProposed(_transactionId, _milestoneId);
    emit Evidence(
      constants.arbitrator,
      getEvidenceGroupId(_transactionId, _milestoneId),
      msg.sender, // What do i put for the party? funders can be many different addresses
      _evidenceUri
    );
  }

  /// @notice See {IFundMeCore} TODO Needs testing
  function claimMilestone(uint32 _transactionId)
    public
    override(IFundMeCore)
    nonReentrant
    transactionExists(_transactionId)
  {
    Transaction storage _transaction = transactions[_transactionId];
    uint16 _milestoneId = _transaction.nextClaimableMilestoneCounter;
    Milestone storage _milestone = _transaction.milestones[_milestoneId];

    if (_milestone.status != Status.Claiming) {
      revert FundMe__MilestoneStatusNotClaiming(_transactionId, _milestoneId);
    }

    // check to see receiverWithdrawTimeout has passed
    if (uint64(block.timestamp) - _transaction.timing.lastInteraction < _transaction.timing.receiverWithdrawTimeout) {
      revert FundMe__RequiredTimeoutNotPassed({
        requiredTimeout: _transaction.timing.receiverWithdrawTimeout,
        timePassed: uint64(block.timestamp) - _transaction.timing.lastInteraction
      });
    }

    // TODO Possibly need more checks.

    _transaction.nextClaimableMilestoneCounter += 1;
    _milestone.status = Status.Resolved;
    accountBalance[_transaction.receiver][address(_transaction.crowdfundToken)] += _milestone.amountClaimable;
    _transaction.transactionFunds.remainingFunds -= _milestone.amountClaimable;

    emit BalanceUpdate(
      _transaction.receiver,
      address(_transaction.crowdfundToken),
      accountBalance[_transaction.receiver][address(_transaction.crowdfundToken)]
    );
    emit MilestoneResolved(_transactionId, _milestoneId);
  }

  /// @notice See {IFundMeCore}
  function rule(uint256 _disputeId, uint256 _ruling) external override(IFundMeCore) {
    if (_ruling > uint256(DisputeChoices.ReceiverWins)) {
      revert FundMe__InvalidRuling({rulingGiven: _ruling, numberOfChoices: uint256(DisputeChoices.ReceiverWins)});
    }

    DisputeChoices ruling = DisputeChoices(_ruling);
    uint32 _localDisputeId = externalDisputeIdToLocalDisputeId[_disputeId];
    DisputeStruct storage dispute = disputes[_localDisputeId];
    Transaction storage _transaction = transactions[dispute.transactionId];
    Milestone storage _milestone = _transaction.milestones[dispute.milestoneId];

    if (msg.sender != address(constants.arbitrator)) {
      revert FundMe__OnlyArbitrator({arbitrator: address(constants.arbitrator)});
    }

    if (dispute.isRuled) {
      revert FundMe__DisputeAlreadyRuled();
    }

    if (_milestone.status != Status.DisputeCreated) {
      revert FundMe__MilestoneStatusNotCreated({
        transactionId: dispute.transactionId,
        milestoneId: dispute.milestoneId
      });
    }

    executeRuling(_localDisputeId, ruling);
  }

  /// @notice See {IFundMeCore} TODO needs testing!
  function createDispute(uint32 _transactionId) public payable override(IFundMeCore) transactionExists(_transactionId) {
    Transaction storage _transaction = transactions[_transactionId];
    uint16 _milestoneId = _transaction.nextClaimableMilestoneCounter;
    Milestone storage _milestone = _transaction.milestones[_milestoneId];
    uint256 arbitrationCost = constants.arbitrator.arbitrationCost(_milestone.arbitratorExtraData);

    if (_milestone.status != Status.Claiming) {
      revert FundMe__MilestoneStatusNotClaiming(_transactionId, _milestoneId);
    }

    _transaction.paidDisputeFees += uint128(msg.value);
    uint256 _refundAmount = 0;

    if (uint256(_transaction.paidDisputeFees) < arbitrationCost) {
      // dispute requires more funds, emit event that indicates this and exit the function
      emit DisputeContribution({
        _transactionId: _transactionId,
        _milestoneId: _milestoneId,
        _contributor: msg.sender,
        _amountContributed: uint128(msg.value),
        _amountRequired: uint128(arbitrationCost),
        _amountPaid: _transaction.paidDisputeFees
      });
      return;
    } else if (uint256(_transaction.paidDisputeFees) > arbitrationCost) {
      // dispute fee was overpaid, adjust account balance, and set disputeFee to the arbitration cost
      _refundAmount = uint256(_transaction.paidDisputeFees) - arbitrationCost;

      accountBalance[msg.sender][address(0)] += _refundAmount;
      _transaction.paidDisputeFees = uint128(arbitrationCost);
      emit BalanceUpdate(msg.sender, address(0), accountBalance[msg.sender][address(0)]);
    }

    // the following will execute only one time, and will only execute when the dispute fee has been fully paid
    emit DisputeContribution({
      _transactionId: _transactionId,
      _milestoneId: _milestoneId,
      _contributor: msg.sender,
      _amountContributed: uint128(msg.value - _refundAmount),
      _amountRequired: _transaction.paidDisputeFees,
      _amountPaid: _transaction.paidDisputeFees
    });

    uint32 localDisputeId = localDisputeIdCounter;
    disputes[localDisputeId] = DisputeStruct({
      transactionId: _transactionId,
      milestoneId: _milestoneId,
      isRuled: false,
      ruling: DisputeChoices(0)
    });

    uint256 externalDisputeId = constants.arbitrator.createDispute{value: arbitrationCost}(
      uint256(DisputeChoices.ReceiverWins), //number of ruling options
      _milestone.arbitratorExtraData
    );

    externalDisputeIdToLocalDisputeId[externalDisputeId] = localDisputeId;
    localDisputeIdCounter += 1;
    _milestone.status = Status.DisputeCreated;

    emit Dispute(
      constants.arbitrator,
      externalDisputeId,
      _transactionId, // transactionId == MetaEvidenceId
      getEvidenceGroupId(_transactionId, _milestoneId)
    );
  }

  /// @notice See {IFundMeCore}
  function withdraw(address tokenAddress) public override(IFundMeCore) nonReentrant {
    uint256 balance = accountBalance[msg.sender][tokenAddress];
    if (balance > 0) {
      if (tokenAddress == address(0)) {
        (bool success, ) = payable(msg.sender).call{value: balance}("");
        // revert if transfer was not successful
        if (!success) {
          revert FundMe__TransferUnsuccessful();
        }
      } else {
        IERC20(tokenAddress).transfer(msg.sender, balance);
      }

      // NOTE contracts with modified fallbacks should still be able to use this contract. We dont want to update balance before incase low level
      // call fails so we modify after the transfer. Still guarded against reentrancy
      accountBalance[msg.sender][tokenAddress] = 0;
    } else {
      revert FundMe__NoWithdrawableFunds();
    }
  }

  /// @notice See {IFundMeCore}
  function refund(uint32 _transactionId) public override(IFundMeCore) nonReentrant transactionExists(_transactionId) {
    Transaction storage _transaction = transactions[_transactionId];

    if (!isFunderRefunded(_transactionId)) {
      uint256 _refundAmount = transactionFunderDetails[_transactionId][msg.sender].amountFunded;
      accountBalance[msg.sender][address(_transaction.crowdfundToken)] += _refundAmount;
      transactionFunderDetails[_transactionId][msg.sender].amountFunded = 0;
      transactionFunderDetails[_transactionId][msg.sender].latestRefundedDisputeId = _transaction.refundableDisputeIds[
        _transaction.refundableDisputeIds.length - 1
      ];
    } else {
      revert FundMe__NoRefundableFunds();
    }
  }

  /// @notice See {IFundMeCore}
  function supportsInterface(bytes4 interfaceId) public view override(ERC165) returns (bool) {
    return interfaceId == type(IFundMeCore).interfaceId || super.supportsInterface(interfaceId);
  }

  /**************************************/
  /**** internal functions **************/
  /**************************************/

  /** @notice execute the ruling and modify the necessary state. called by rule()
   *  @param _localDisputeId local ID of the dispute.
   *  @param _ruling ruling ID in the form of DisputeChoices enum.
   *  TODO Needs testing
   */
  function executeRuling(uint32 _localDisputeId, DisputeChoices _ruling) internal {
    DisputeStruct storage _dispute = disputes[_localDisputeId];
    Transaction storage _transaction = transactions[_dispute.transactionId];
    Milestone storage _milestone = _transaction.milestones[_dispute.milestoneId];

    _dispute.isRuled = true;
    _dispute.ruling = _ruling;
    _transaction.paidDisputeFees = 0;

    if (_ruling == DisputeChoices.ReceiverWins) {
      // maybe have to set timing.lastInteraction to 0 value so claim milestone can be called?
      _transaction.timing.lastInteraction = 0;
      _milestone.status = Status.Claiming;
      claimMilestone(_dispute.transactionId);
    } else if (_ruling == DisputeChoices.FunderWins) {
      refundFunders(_dispute.transactionId, _localDisputeId);
    } else {
      // TODO ruling was 'Refused to arbitrate', what to do here? For now refund the funders, the onus is on the receiver to submit meaningful evidence
      refundFunders(_dispute.transactionId, _localDisputeId);
    }
  }

  /** @notice modifies necessary state to refund the funders. NOTE that the funders still have to call refund() to actually have their funds refunded,
   *          and have to call withdraw() to actually withdraw refunded funds.
   *  @param _transactionId ID of the transaction.
   *  @param _localDisputeId local ID of the dispute.
   *  TODO Needs testing
   */
  function refundFunders(uint32 _transactionId, uint32 _localDisputeId) internal {
    Transaction storage _transaction = transactions[_transactionId];
    uint16 _milestoneId = _transaction.nextClaimableMilestoneCounter;
    Milestone storage _milestone = _transaction.milestones[_milestoneId];

    _transaction.refundableDisputeIds.push(_localDisputeId);

    _transaction.transactionFunds.totalFunded -= _transaction.transactionFunds.remainingFunds;
    _transaction.transactionFunds.remainingFunds = 0;
    _milestone.status = Status.Created;
  }

  /** @notice calculate the amountClaimable based on the REMAINING milestones left to claim and the transaction remainingFunds
   *  @param _transactionId ID of the transaction.
   *  @dev The reason we need to calculate the percentage claimable based on the remaining transactions is because funds
   *  can keep being added to the transaction after a milestone is claimed if funders want to continue supporting it.
   *  if we were to use the original milestone amountUnlockablePercentage to calculate milestone amountClaimable the total
   *  amount withdrawable would always be <= totalFunds deposited.
   *  TODO Needs testing
   */
  function getMilestoneAmountClaimable(uint32 _transactionId) internal view returns (uint256 amountClaimable) {
    Transaction memory _transaction = transactions[_transactionId];
    uint16 _milestoneId = _transaction.nextClaimableMilestoneCounter;

    uint64[] memory remainingMilestonesAmountUnlockable = new uint64[](_transaction.milestones.length - _milestoneId);
    // put the remaining milestones amountUnlockablePercentage into an array
    for (uint16 i = 0; i < remainingMilestonesAmountUnlockable.length; i++) {
      remainingMilestonesAmountUnlockable[i] = _transaction.milestones[i + _milestoneId].amountUnlockablePercentage;
    }

    // sum of remaining milestones amountUnlockablePercentage will total < 100% (1 ether). dividing each remaining milestone
    // amountUnlockablePercentage by the sum of all remaining amountUnlockablePercentage, and recalculating the sum of all those
    // values will yield a total of 100% (1 ether). since we only require percentage claimable for the given milestone, we only
    // calculate percentage claimable for the first index of the remaining milestones amountUnlockablePercentage
    uint256 percentageClaimable = (uint256(remainingMilestonesAmountUnlockable[0]) * 1 ether) /
      remainingMilestonesAmountUnlockable.getSum();
    // now we can calculate the amountClaimable of the erc20 crowdFundToken. since percentageClaimable is denominated by 1 ether
    // we must divide by 1 ether in order to to get an actual percentage as a fraction (if percentageClaimable for a given
    // milestone was 0.2 ether the amount claimable should be remainingFunds * 0.2, NOT remainingFunds * 0.2 ether)
    amountClaimable = (_transaction.transactionFunds.remainingFunds * percentageClaimable) / 1 ether;
  }

  /** @notice check if the funder has been refunded
   *  @param _transactionId ID of the transaction
   *  @dev if the latest disputeId the funder has been refunded for is less than the transactions latest disputeId then we know that the funder has not
   *  been refunded because disputeIds are always incrementing so if theres a new dispute, than its dispute id will always be greater than the disputeId
   *  the funder has been refunded for IF they have not been refunded for the latest dispute, otherwise they will be equal
   *  TODO Needs testing
   */
  function isFunderRefunded(uint32 _transactionId) internal view returns (bool) {
    Transaction memory _transaction = transactions[_transactionId];

    // if there has not been any disputes for this transaction, set the latestDisputeId to 0 then this function will automatically return true
    uint32 latestDisputeId = (_transaction.refundableDisputeIds.length != 0)
      ? _transaction.refundableDisputeIds[_transaction.refundableDisputeIds.length - 1]
      : 0;
    uint32 latestRefundedDisputeId = transactionFunderDetails[_transactionId][msg.sender].latestRefundedDisputeId;

    return
      (latestRefundedDisputeId < latestDisputeId &&
        transactionFunderDetails[_transactionId][msg.sender].amountFunded > 0)
        ? false
        : true;
  }

  /** @notice check if the funder has never funded this transaction, and if it has been previously disputed, update the necessary state
   *  @param _transactionId ID of the transaction
   *  @dev Covers the edge case where a funder has never funded a disputed transaction. They should still be able to fund this transaction, so we
           need to adjust the latestRefundedDisputeId. NOTE The UI should acknowledge the user that they are funding a preivously dispute transaction
   *  TODO Needs testing
   */
  function hasFunderNeverFundedDisputedTransaction(uint32 _transactionId) internal {
    Transaction memory _transaction = transactions[_transactionId];

    // if there has not been any disputes for this transaction, set the latestDisputeId to 0 then this function will do nothing
    uint32 latestDisputeId = (_transaction.refundableDisputeIds.length != 0)
      ? _transaction.refundableDisputeIds[_transaction.refundableDisputeIds.length - 1]
      : 0;
    uint32 latestRefundedDisputeId = transactionFunderDetails[_transactionId][msg.sender].latestRefundedDisputeId;

    if (
      latestRefundedDisputeId < latestDisputeId &&
      transactionFunderDetails[_transactionId][msg.sender].amountFunded == 0
    ) {
      transactionFunderDetails[_transactionId][msg.sender].latestRefundedDisputeId = latestDisputeId;
    }
  }

  /**************************************/
  /**** public getters ******************/
  /**************************************/

  /** @notice fetch a transaction given a transactionId
   *  @param transactionId ID of the transaction.
   */
  function getTransaction(uint32 transactionId) public view returns (Transaction memory _transaction) {
    _transaction = transactions[transactionId];
  }

  /** @notice fetch a milestone given a transactionId and milestoneId
   *  @param transactionId ID of the transaction.
   *  @param milestoneId ID of the milestone.
   *  @dev milestoneId is indexed starting at 0 for every transaction. That is milestoneId's are NOT unique between transactions.
   */
  function getTransactionMilestone(uint32 transactionId, uint16 milestoneId)
    public
    view
    returns (Milestone memory _milestone)
  {
    _milestone = transactions[transactionId].milestones[milestoneId];
  }

  /** @notice get evidenceGroupId for a given transactionId, and milestoneId. this allows us to create a unique id for the evidence group.
   *  @param transactionId ID of the transaction.
   *  @param milestoneId ID of the milestone.
   *  @dev bitwise shift allows us to create unique id. this should be safe since transactionId and milestoneId will never exceed 2^128
   *       this can be decoded if needed by: _transactionId = uint128(_evidenceGroupId >> 128); _milestoneId = uint128(_evidenceGroupId);
   */
  function getEvidenceGroupId(uint32 transactionId, uint16 milestoneId) public pure returns (uint256 evidenceGroupId) {
    evidenceGroupId = (uint256(transactionId) << 128) + uint256(milestoneId);
  }
}
