// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "hardhat/console.sol";

/** @title FundMe
 *  A contract storing ERC20 tokens raised in a crowdfunding event.
 */
library Arrays64 {
  error IndexGreaterThanArrayLength();

  /** @notice Get the sum of all elements in the array
   *  @param _array The array used for calculation
   *  @dev time complexity is O(n)
   */
  function getSum(uint64[] memory _array) internal pure returns (uint64 sum) {
    for (uint16 idx = 0; idx < _array.length; idx++) {
      sum += _array[idx];
    }
  }

  /** @notice remove an index from an array
   *  @param _array The array used for calculation
   *  @param _index The index to remove from the array NOTE that the index should not exceed 2^16
   *  @dev worst case time complexity is O(n)
   */
  function removeIndex(uint64[] storage _array, uint16 _index) internal {
    if (_index >= _array.length) {
      revert IndexGreaterThanArrayLength();
    }

    for (uint16 i = _index; i < _array.length - 1; i++) {
      _array[i] = _array[i + 1];
    }
    _array.pop();
  }
}
