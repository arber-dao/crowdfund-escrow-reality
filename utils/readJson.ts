const path = require("path")
const fsPromises = require("fs/promises")

export const readJson = async (filePath: string) => {
  try {
    const file = path.resolve(filePath)

    // Get the content of the JSON file
    const data = await fsPromises.readFile(file)

    // Turn it to an object
    const obj = JSON.parse(data)

    return obj
  } catch (err) {
    console.error(err)
  }
}
