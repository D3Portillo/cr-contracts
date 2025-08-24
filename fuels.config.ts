import { createConfig } from "fuels"

export default createConfig({
  contracts: ["src"],
  output: "./abi_types",
})

/**
 * Check the docs:
 * https://docs.fuel.network/docs/fuels-ts/fuels-cli/config-file/
 */
