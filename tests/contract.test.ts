import { launchTestNode, TestAssetId } from "fuels/test-utils"
import { describe, test, expect } from "vitest"
import { BasicPoolFactory } from "../abi_types/BasicPoolFactory"

describe("Basic Pool Contract Tests", () => {
  test("Rewards are disbursed", async () => {
    const winner_riot_id = 1
    const loser_riot_id = 2
    const DEPOSIT_AMOUNT = 1

    const testNode = await launchTestNode({
      walletsConfig: {
        count: 4,
        assets: [TestAssetId.A, TestAssetId.B],
      },
      contractsConfigs: [
        {
          factory: BasicPoolFactory,
        },
      ],
    })

    const {
      contracts: [contract],
      provider,
    } = testNode

    const owner = testNode.wallets[0]

    contract.account = owner
    await contract.functions.initialize().call()
    await contract.functions.start_challenge().call()

    const BASE_ASSET_ID = await provider.getBaseAssetId()

    const getAccountBalance = async (accountAddress: any) => {
      return await contract.provider.getBalance(accountAddress, BASE_ASSET_ID)
    }

    await contract.functions
      .deposit_for_riot(loser_riot_id)
      .callParams({
        forward: [DEPOSIT_AMOUNT, BASE_ASSET_ID],
      })
      .call()

    let tvl = await contract.functions.get_riot_tvl(loser_riot_id).get()
    expect(tvl.value.toNumber()).toEqual(1)

    /**
     * Deposit for winner riot
     */

    contract.account = testNode.wallets[1]
    await contract.functions
      .deposit_for_riot(winner_riot_id)
      .callParams({
        forward: [DEPOSIT_AMOUNT, BASE_ASSET_ID],
      })
      .call()

    tvl = await contract.functions.get_pool_tvl().get()
    expect(tvl.value.toNumber()).toEqual(2)

    const winner = contract.account
    const initialWinnerBalance = await getAccountBalance(winner.address)

    // Stop Challenge
    contract.account = owner
    const res = await contract.functions
      .stop_challenge(winner_riot_id, true, 0)
      .call()

    await res.waitForResult()

    // Check for ZERO TVL
    tvl = await contract.functions.get_pool_tvl().get()
    expect(tvl.value.toNumber()).toEqual(0)

    // Check winner got reward + deposit back
    expect(initialWinnerBalance.toNumber() + DEPOSIT_AMOUNT * 2).toEqual(
      (await getAccountBalance(winner.address)).toNumber()
    )
  })
})
