const { dirname } = require("path")
export const getProjectRoot = dirname(__dirname, "..")

export const sleep = async (time: number) => {
  return new Promise((res) => {
    setTimeout(() => {
      res(undefined)
    }, time)
  })
}

/********************** */
