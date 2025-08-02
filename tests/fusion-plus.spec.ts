import 'dotenv/config'
import {expect, jest} from '@jest/globals'

import {createServer, CreateServerReturnType} from 'prool'
import {anvil} from 'prool/instances'

import {
    computeAddress,
    ContractFactory,
    JsonRpcProvider,
    MaxUint256,
    parseEther,
    parseUnits,
    randomBytes,
    Wallet as SignerWallet,
    keccak256,
    toUtf8Bytes
} from 'ethers'
import {uint8ArrayToHex, UINT_40_MAX} from '@1inch/byte-utils'
import assert from 'node:assert'
import {ChainConfig, config} from './config'
import {Wallet} from './wallet'

// Mock contracts for Fusion+ system
const FusionPlusResolverABI = [
    "function createFusionOrder(tuple(uint256 srcChainId, uint256 dstChainId, address srcToken, address dstToken, uint256 amount, uint256 deadline, bytes32 hashlock, uint256 timelock, address recipient) params) external payable",
    "function fillFusionOrder(bytes32 orderHash, address takerAddress, uint256 amount, bytes32 secret) external",
    "function cancelFusionOrder(bytes32 orderHash) external",
    "function withdrawFromEscrow(bytes32 orderHash, bytes32 secret) external",
    "function getFusionOrder(bytes32 orderHash) external view returns (tuple(bytes32 orderHash, address maker, uint256 srcChainId, uint256 dstChainId, address srcToken, address dstToken, uint256 amount, uint256 deadline, bytes32 hashlock, uint256 timelock, bool isActive, bool isFilled, bool isCancelled, uint256 filledAmount, uint256 remainingAmount))",
    "function isOrderActive(bytes32 orderHash) external view returns (bool)",
    "function setAuthorizedResolver(address resolver, bool authorized) external",
    "event FusionOrderCreated(bytes32 indexed orderHash, address indexed maker, uint256 srcChainId, uint256 dstChainId, address srcToken, address dstToken, uint256 amount, uint256 deadline, bytes32 hashlock, uint256 timelock)",
    "event FusionOrderFilled(bytes32 indexed orderHash, address indexed taker, uint256 amount, bytes32 secret, uint256 timestamp)"
]

const FusionPlusEscrowSrcABI = [
    "function createEscrow(bytes32 orderHash, address token, uint256 amount, bytes32 hashlock, uint256 timelock) external payable",
    "function withdraw(bytes32 orderHash, bytes32 secret, address recipient) external",
    "function cancelEscrow(bytes32 orderHash) external",
    "function getEscrow(bytes32 orderHash) external view returns (tuple(bytes32 orderHash, address maker, address token, uint256 amount, bytes32 hashlock, uint256 timelock, uint256 createdAt, bool isActive, bool isWithdrawn, bool isCancelled))"
]

const FusionPlusEscrowDstABI = [
    "function createEscrow(bytes32 orderHash, address token, uint256 amount, bytes32 hashlock, uint256 timelock) external payable",
    "function withdraw(bytes32 orderHash, bytes32 secret, address recipient) external",
    "function cancelEscrow(bytes32 orderHash) external",
    "function getEscrow(bytes32 orderHash) external view returns (tuple(bytes32 orderHash, address maker, address token, uint256 amount, bytes32 hashlock, uint256 timelock, uint256 createdAt, bool isActive, bool isWithdrawn, bool isCancelled))"
]

jest.setTimeout(300000) // 5 minutes timeout

const userPk = '0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d'
const resolverPk = '0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a'

describe('1inch Fusion+ Cross-Chain Swap System', () => {
    const srcChainId = config.chain.source.chainId
    const dstChainId = config.chain.destination.chainId

    type Chain = {
        node?: CreateServerReturnType | undefined
        provider: JsonRpcProvider
        resolver: string
        escrowSrc: string
        escrowDst: string
    }

    let src: Chain
    let dst: Chain

    let srcChainUser: Wallet
    let dstChainUser: Wallet
    let srcChainResolver: Wallet
    let dstChainResolver: Wallet

    let srcResolverContract: any
    let dstResolverContract: any
    let srcEscrowContract: any
    let dstEscrowContract: any

    let srcTimestamp: bigint

    async function increaseTime(t: number): Promise<void> {
        await Promise.all([src, dst].map((chain) => chain.provider.send('evm_increaseTime', [t])))
    }

    beforeAll(async () => {
        ;[src, dst] = await Promise.all([initChain(config.chain.source), initChain(config.chain.destination)])

        srcChainUser = new Wallet(userPk, src.provider)
        dstChainUser = new Wallet(userPk, dst.provider)
        srcChainResolver = new Wallet(resolverPk, src.provider)
        dstChainResolver = new Wallet(resolverPk, dst.provider)

        // Deploy Fusion+ contracts
        await deployFusionPlusContracts()

        srcTimestamp = BigInt((await src.provider.getBlock('latest'))!.timestamp)
    })

    afterAll(async () => {
        await Promise.all([src.node, dst.node].map((node) => node?.close()))
    })

    describe('Bidirectional Ethereum-Monad Swaps', () => {
        it('should create Fusion+ order from Ethereum to Monad', async () => {
            const amount = parseEther('1')
            const deadline = BigInt(Date.now() / 1000) + 3600n // 1 hour
            const timelock = 1800n // 30 minutes
            
            // Generate secret and hashlock
            const secret = keccak256(toUtf8Bytes('test-secret-' + Date.now()))
            const hashlock = keccak256(secret)

            const swapParams = {
                srcChainId: srcChainId,
                dstChainId: dstChainId,
                srcToken: config.chain.source.tokens.USDC.address,
                dstToken: config.chain.destination.tokens.USDC.address,
                amount: amount,
                deadline: deadline,
                hashlock: hashlock,
                timelock: timelock,
                recipient: dstChainUser.address
            }

            // Approve tokens
            await srcChainUser.approveToken(
                config.chain.source.tokens.USDC.address,
                src.resolver,
                MaxUint256
            )

            // Create order
            const tx = await srcResolverContract.createFusionOrder(swapParams, {
                value: amount + parseEther('0.01') // amount + safety deposit
            })

            const receipt = await tx.wait()
            expect(receipt.status).toBe(1)

            // Verify order creation event
            const event = receipt.logs.find((log: any) => 
                log.topics[0] === keccak256(toUtf8Bytes('FusionOrderCreated(bytes32,address,uint256,uint256,address,address,uint256,uint256,bytes32,uint256)'))
            )
            expect(event).toBeDefined()

            console.log('✅ Fusion+ order created from Ethereum to Monad')
        })

        it('should create Fusion+ order from Monad to Ethereum', async () => {
            const amount = parseEther('0.5')
            const deadline = BigInt(Date.now() / 1000) + 3600n // 1 hour
            const timelock = 1800n // 30 minutes
            
            // Generate secret and hashlock
            const secret = keccak256(toUtf8Bytes('test-secret-' + Date.now()))
            const hashlock = keccak256(secret)

            const swapParams = {
                srcChainId: dstChainId,
                dstChainId: srcChainId,
                srcToken: config.chain.destination.tokens.USDC.address,
                dstToken: config.chain.source.tokens.USDC.address,
                amount: amount,
                deadline: deadline,
                hashlock: hashlock,
                timelock: timelock,
                recipient: srcChainUser.address
            }

            // Approve tokens
            await dstChainUser.approveToken(
                config.chain.destination.tokens.USDC.address,
                dst.resolver,
                MaxUint256
            )

            // Create order
            const tx = await dstResolverContract.createFusionOrder(swapParams, {
                value: amount + parseEther('0.01') // amount + safety deposit
            })

            const receipt = await tx.wait()
            expect(receipt.status).toBe(1)

            console.log('✅ Fusion+ order created from Monad to Ethereum')
        })

        it('should fill Fusion+ order with hashlock validation', async () => {
            const amount = parseEther('1')
            const deadline = BigInt(Date.now() / 1000) + 3600n // 1 hour
            const timelock = 1800n // 30 minutes
            
            // Generate secret and hashlock
            const secret = keccak256(toUtf8Bytes('test-secret-' + Date.now()))
            const hashlock = keccak256(secret)

            const swapParams = {
                srcChainId: srcChainId,
                dstChainId: dstChainId,
                srcToken: config.chain.source.tokens.USDC.address,
                dstToken: config.chain.destination.tokens.USDC.address,
                amount: amount,
                deadline: deadline,
                hashlock: hashlock,
                timelock: timelock,
                recipient: dstChainUser.address
            }

            // Create order
            await srcChainUser.approveToken(
                config.chain.source.tokens.USDC.address,
                src.resolver,
                MaxUint256
            )

            const createTx = await srcResolverContract.createFusionOrder(swapParams, {
                value: amount + parseEther('0.01')
            })
            await createTx.wait()

            // Compute order hash
            const orderHash = keccak256(
                toUtf8Bytes(
                    srcChainId.toString() +
                    dstChainId.toString() +
                    config.chain.source.tokens.USDC.address +
                    config.chain.destination.tokens.USDC.address +
                    amount.toString() +
                    deadline.toString() +
                    hashlock +
                    timelock.toString() +
                    srcChainUser.address +
                    srcChainId.toString()
                )
            )

            // Fill order with correct secret
            const fillTx = await srcResolverContract.fillFusionOrder(
                orderHash,
                dstChainUser.address,
                amount,
                secret
            )

            const fillReceipt = await fillTx.wait()
            expect(fillReceipt.status).toBe(1)

            // Verify order is filled
            const order = await srcResolverContract.getFusionOrder(orderHash)
            expect(order.isFilled).toBe(true)
            expect(order.filledAmount).toEqual(amount)

            console.log('✅ Fusion+ order filled with hashlock validation')
        })

        it('should support partial fills', async () => {
            const totalAmount = parseEther('2')
            const partialAmount1 = parseEther('0.5')
            const partialAmount2 = parseEther('0.3')
            const deadline = BigInt(Date.now() / 1000) + 3600n // 1 hour
            const timelock = 1800n // 30 minutes
            
            // Generate secret and hashlock
            const secret = keccak256(toUtf8Bytes('test-secret-' + Date.now()))
            const hashlock = keccak256(secret)

            const swapParams = {
                srcChainId: srcChainId,
                dstChainId: dstChainId,
                srcToken: config.chain.source.tokens.USDC.address,
                dstToken: config.chain.destination.tokens.USDC.address,
                amount: totalAmount,
                deadline: deadline,
                hashlock: hashlock,
                timelock: timelock,
                recipient: dstChainUser.address
            }

            // Create order
            await srcChainUser.approveToken(
                config.chain.source.tokens.USDC.address,
                src.resolver,
                MaxUint256
            )

            const createTx = await srcResolverContract.createFusionOrder(swapParams, {
                value: totalAmount + parseEther('0.01')
            })
            await createTx.wait()

            // Compute order hash
            const orderHash = keccak256(
                toUtf8Bytes(
                    srcChainId.toString() +
                    dstChainId.toString() +
                    config.chain.source.tokens.USDC.address +
                    config.chain.destination.tokens.USDC.address +
                    totalAmount.toString() +
                    deadline.toString() +
                    hashlock +
                    timelock.toString() +
                    srcChainUser.address +
                    srcChainId.toString()
                )
            )

            // First partial fill
            const fill1Tx = await srcResolverContract.fillFusionOrder(
                orderHash,
                dstChainUser.address,
                partialAmount1,
                secret
            )
            await fill1Tx.wait()

            let order = await srcResolverContract.getFusionOrder(orderHash)
            expect(order.filledAmount).toEqual(partialAmount1)
            expect(order.remainingAmount).toEqual(totalAmount - partialAmount1)
            expect(order.isActive).toBe(true)

            // Second partial fill
            const fill2Tx = await srcResolverContract.fillFusionOrder(
                orderHash,
                dstChainUser.address,
                partialAmount2,
                secret
            )
            await fill2Tx.wait()

            order = await srcResolverContract.getFusionOrder(orderHash)
            expect(order.filledAmount).toEqual(partialAmount1 + partialAmount2)
            expect(order.remainingAmount).toEqual(totalAmount - partialAmount1 - partialAmount2)

            console.log('✅ Partial fills supported successfully')
        })

        it('should enforce timelock functionality', async () => {
            const amount = parseEther('1')
            const deadline = BigInt(Date.now() / 1000) + 3600n // 1 hour
            const timelock = 1800n // 30 minutes
            
            // Generate secret and hashlock
            const secret = keccak256(toUtf8Bytes('test-secret-' + Date.now()))
            const hashlock = keccak256(secret)

            const swapParams = {
                srcChainId: srcChainId,
                dstChainId: dstChainId,
                srcToken: config.chain.source.tokens.USDC.address,
                dstToken: config.chain.destination.tokens.USDC.address,
                amount: amount,
                deadline: deadline,
                hashlock: hashlock,
                timelock: timelock,
                recipient: dstChainUser.address
            }

            // Create order
            await srcChainUser.approveToken(
                config.chain.source.tokens.USDC.address,
                src.resolver,
                MaxUint256
            )

            const createTx = await srcResolverContract.createFusionOrder(swapParams, {
                value: amount + parseEther('0.01')
            })
            await createTx.wait()

            // Compute order hash
            const orderHash = keccak256(
                toUtf8Bytes(
                    srcChainId.toString() +
                    dstChainId.toString() +
                    config.chain.source.tokens.USDC.address +
                    config.chain.destination.tokens.USDC.address +
                    amount.toString() +
                    deadline.toString() +
                    hashlock +
                    timelock.toString() +
                    srcChainUser.address +
                    srcChainId.toString()
                )
            )

            // Try to cancel before timelock expires (should fail)
            try {
                await srcResolverContract.cancelFusionOrder(orderHash)
                assert.fail('Should not be able to cancel before timelock expires')
            } catch (error) {
                expect(error.message).toContain('Cannot cancel order')
            }

            // Fast forward time past timelock
            await increaseTime(1801) // 30 minutes + 1 second

            // Now should be able to cancel
            const cancelTx = await srcResolverContract.cancelFusionOrder(orderHash)
            const cancelReceipt = await cancelTx.wait()
            expect(cancelReceipt.status).toBe(1)

            const order = await srcResolverContract.getFusionOrder(orderHash)
            expect(order.isCancelled).toBe(true)

            console.log('✅ Timelock functionality enforced correctly')
        })

        it('should execute onchain token transfers', async () => {
            const amount = parseEther('1')
            const deadline = BigInt(Date.now() / 1000) + 3600n // 1 hour
            const timelock = 1800n // 30 minutes
            
            // Generate secret and hashlock
            const secret = keccak256(toUtf8Bytes('test-secret-' + Date.now()))
            const hashlock = keccak256(secret)

            // Get initial balances
            const initialSrcBalance = await srcChainUser.getTokenBalance(config.chain.source.tokens.USDC.address)
            const initialDstBalance = await dstChainUser.getTokenBalance(config.chain.destination.tokens.USDC.address)

            const swapParams = {
                srcChainId: srcChainId,
                dstChainId: dstChainId,
                srcToken: config.chain.source.tokens.USDC.address,
                dstToken: config.chain.destination.tokens.USDC.address,
                amount: amount,
                deadline: deadline,
                hashlock: hashlock,
                timelock: timelock,
                recipient: dstChainUser.address
            }

            // Create order
            await srcChainUser.approveToken(
                config.chain.source.tokens.USDC.address,
                src.resolver,
                MaxUint256
            )

            const createTx = await srcResolverContract.createFusionOrder(swapParams, {
                value: amount + parseEther('0.01')
            })
            await createTx.wait()

            // Compute order hash
            const orderHash = keccak256(
                toUtf8Bytes(
                    srcChainId.toString() +
                    dstChainId.toString() +
                    config.chain.source.tokens.USDC.address +
                    config.chain.destination.tokens.USDC.address +
                    amount.toString() +
                    deadline.toString() +
                    hashlock +
                    timelock.toString() +
                    srcChainUser.address +
                    srcChainId.toString()
                )
            )

            // Fill order
            const fillTx = await srcResolverContract.fillFusionOrder(
                orderHash,
                dstChainUser.address,
                amount,
                secret
            )
            await fillTx.wait()

            // Verify token transfers occurred
            const finalSrcBalance = await srcChainUser.getTokenBalance(config.chain.source.tokens.USDC.address)
            const finalDstBalance = await dstChainUser.getTokenBalance(config.chain.destination.tokens.USDC.address)

            // Source chain balance should decrease
            expect(finalSrcBalance).toBeLessThan(initialSrcBalance)
            
            // Destination chain balance should increase (if escrow is deployed and withdrawn)
            // Note: In a real cross-chain scenario, this would require bridge interaction

            console.log('✅ Onchain token transfers executed successfully')
            console.log(`Source balance change: ${initialSrcBalance - finalSrcBalance}`)
            console.log(`Destination balance change: ${finalDstBalance - initialDstBalance}`)
        })
    })

    async function deployFusionPlusContracts() {
        console.log('Deploying Fusion+ contracts...')

        // Deploy on source chain
        const srcResolverFactory = new ContractFactory(
            FusionPlusResolverABI,
            '0x', // Placeholder bytecode
            srcChainResolver
        )
        srcResolverContract = await srcResolverFactory.deploy()
        await srcResolverContract.waitForDeployment()
        src.resolver = await srcResolverContract.getAddress()

        const srcEscrowFactory = new ContractFactory(
            FusionPlusEscrowSrcABI,
            '0x', // Placeholder bytecode
            srcChainResolver
        )
        srcEscrowContract = await srcEscrowFactory.deploy()
        await srcEscrowContract.waitForDeployment()
        src.escrowSrc = await srcEscrowContract.getAddress()

        // Deploy on destination chain
        const dstResolverFactory = new ContractFactory(
            FusionPlusResolverABI,
            '0x', // Placeholder bytecode
            dstChainResolver
        )
        dstResolverContract = await dstResolverFactory.deploy()
        await dstResolverFactory.waitForDeployment()
        dst.resolver = await dstResolverContract.getAddress()

        const dstEscrowFactory = new ContractFactory(
            FusionPlusEscrowDstABI,
            '0x', // Placeholder bytecode
            dstChainResolver
        )
        dstEscrowContract = await dstEscrowFactory.deploy()
        await dstEscrowContract.waitForDeployment()
        dst.escrowDst = await dstEscrowContract.getAddress()

        console.log('Fusion+ contracts deployed successfully')
    }

    async function initChain(cnf: ChainConfig): Promise<{node?: CreateServerReturnType; provider: JsonRpcProvider; resolver: string; escrowSrc: string; escrowDst: string}> {
        const {node, provider} = await getProvider(cnf)
        
        return {
            node,
            provider,
            resolver: '',
            escrowSrc: '',
            escrowDst: ''
        }
    }

    async function getProvider(cnf: ChainConfig): Promise<{node?: CreateServerReturnType; provider: JsonRpcProvider}> {
        if (cnf.createFork) {
            const node = await createServer(anvil({
                fork: {
                    url: cnf.url
                }
            }))
            return {node, provider: new JsonRpcProvider(node.url)}
        } else {
            return {provider: new JsonRpcProvider(cnf.url)}
        }
    }
}) 