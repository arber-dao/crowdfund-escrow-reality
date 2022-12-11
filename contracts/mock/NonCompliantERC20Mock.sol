// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract NonCompliantERC20Mock is ERC721 {
  uint256 private s_tokenCounter;

  constructor() ERC721("CoolNFT", "CNFT") {
    s_tokenCounter = 0;
    _safeMint(msg.sender, s_tokenCounter);
    s_tokenCounter += 1;
  }

  function getTokenCounter() public view returns (uint256) {
    return s_tokenCounter;
  }
}
