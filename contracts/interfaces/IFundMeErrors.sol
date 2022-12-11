// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./IFundMeCore.sol";

/** @title FundMeErrors
 *  Errors for FundMeCore Contract
 */
interface IFundMeErrors {
  /** @notice throw when msg.sender tries to call a function that only the transaction receiver has access to call
   *  @param receiver the authorized receiver
   */
  error FundMe__OnlyTransactionReceiver(address receiver);

  /** @notice throw when msg.sender tries to call a function that only the arbitrator has access to call
   *  @param arbitrator the authorized arbitrator
   */
  error FundMe__OnlyArbitrator(address arbitrator);

  /** @notice throw when payment to a payable function is not enough
   *  @param amountRequired amount required to complete the transaction
   *  @param amountSent amount sent with the transaction
   */
  error FundMe__PaymentTooSmall(uint128 amountRequired, uint128 amountSent);

  /** @notice throw when the requested transaction does not exist
   *  @param transactionId the id of the requested transaction
   */
  error FundMe__TransactionNotFound(uint32 transactionId);

  /// @notice throw when transfer unsuccessful
  error FundMe__TransferUnsuccessful();

  /** @notice throw when a required amount of time has not yet passed. ie. block.timestamp - lastInteraction < requiredTimeout
   *  @param requiredTimeout the amount of time required to pass
   *  @param timePassed the current amount of time that has passed
   */
  error FundMe__RequiredTimeoutNotPassed(uint64 requiredTimeout, uint64 timePassed);

  /** @notice throw when erc20 contract does not comply to normal erc20 interface
   *  @param nonCompliantErc20 the contract address that failed token transfer
   */
  error FundMe__NonCompliantERC20(address nonCompliantErc20);

  /// @notice throw when there is a milestone data mismatch such as length of milestone arrays passed to createTransaction
  ///         for milestone data are not the same
  error FundMe__MilestoneDataMismatch();

  /** @notice throw when milestone status is not set to Created
   *  @param transactionId ID of the transaction
   *  @param milestoneId ID of the milestone
   */
  error FundMe__MilestoneStatusNotCreated(uint32 transactionId, uint16 milestoneId);

  /** @notice throw when milestone status is not set to Claiming
   *  @param transactionId ID of the transaction
   *  @param milestoneId ID of the milestone
   */
  error FundMe__MilestoneStatusNotClaiming(uint32 transactionId, uint16 milestoneId);

  /** @notice throw when receiver tries to initilize incorrect number of milestones
   *  @param min min number of allowed milestones
   *  @param max max number of allowed milestones
   */
  error FundMe__IncorrectNumberOfMilestoneInitilized(uint16 min, uint16 max);

  /// @notice throw when a transactions sum of all milestones amountUnlockable does not total 1 ether
  error FundMe__MilestoneAmountUnlockablePercentageNot1();

  /// @notice throw when the zero address is not a useable address
  error FundMe__ZeroAddressInvalid();

  /// @notice throw when the FundMe contract address is not a useable address
  error FundMe__FundMeContractAddressInvalid();

  /// @notice throw when there are no funds to withdraw
  error FundMe__NoWithdrawableFunds();

  /// @notice throw when there are no funds to refund
  error FundMe__NoRefundableFunds();

  /** @notice throw when funder attempts to fund a transaction, but has not yet been refunded for a previous dispute on the transaction
   *  @param latestDisputeId the id for the latest dispute on the transaction
   */
  error FundMe__NotRefundedForDispute(uint32 latestDisputeId);

  /** @notice throw when arbitrator gives an invalid ruling
   *  @param rulingGiven min number of allowed milestones
   *  @param numberOfChoices max number of allowed milestones
   */
  error FundMe__InvalidRuling(uint256 rulingGiven, uint256 numberOfChoices);

  /// @notice throw when the dispute has already been ruled upon
  error FundMe__DisputeAlreadyRuled();
}
