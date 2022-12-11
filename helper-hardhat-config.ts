export interface networkConfigItem {
  blockConfirmations?: number
}

export interface networkConfigInfo {
  [key: string]: networkConfigItem
}

export const networkConfig: networkConfigInfo = {
  localhost: {
    blockConfirmations: 1,
  },
  hardhat: {
    blockConfirmations: 1,
  },
  rinkeby: {
    blockConfirmations: 1,
  },
  kovan: {
    blockConfirmations: 1,
  },
}

export const developmentChains = ["hardhat", "localhost"]

// Governor Values
export const QUORUM_PERCENTAGE = 4 // Need 4% of voters to pass
export const MIN_DELAY = 3600 // 1 hour - after a vote passes, you have 1 hour before you can enact
// export const VOTING_PERIOD = 45818 // 1 week - how long the vote lasts. This is pretty long even for local tests
export const VOTING_PERIOD = 5 // blocks
export const VOTING_DELAY = 1 // 1 Block - How many blocks till a proposal vote becomes active
