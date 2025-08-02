// Mock implementation of @1inch/cross-chain-sdk
// This replaces the private package with basic functionality for testing

export class Address {
    constructor(public value: string) {}
    
    toString(): string {
        return this.value;
    }
    
    static fromBigInt(value: bigint): Address {
        return new Address(`0x${value.toString(16).padStart(40, '0')}`);
    }
}

export class HashLock {
    constructor(public value: string) {}
    
    static forSingleFill(secret: string): HashLock {
        // Ensure we have a proper 32-byte hex string
        const hash = `0x${Buffer.from(secret).toString('hex').padEnd(64, '0').substring(0, 64)}`;
        return new HashLock(hash);
    }
    
    static forMultipleFills(leaves: string[]): HashLock {
        // For multiple fills, use a simple hash of the leaves
        const combined = leaves.join('');
        const hash = `0x${Buffer.from(combined).toString('hex').padEnd(64, '0').substring(0, 64)}`;
        return new HashLock(hash);
    }
    
    static hashSecret(secret: string): string {
        return `0x${Buffer.from(secret).toString('hex').padEnd(64, '0').substring(0, 64)}`;
    }
    
    static getMerkleLeaves(secrets: string[]): string[] {
        return secrets.map(s => this.hashSecret(s));
    }
    
    static getProof(leaves: string[], index: number): string[] {
        // Mock implementation - return empty array for now
        return [];
    }
    
    static fromString(value: string): HashLock {
        // Ensure the value is a proper 32-byte hex string
        const hash = value.startsWith('0x') ? value : `0x${value}`;
        return new HashLock(hash.padEnd(66, '0').substring(0, 66));
    }
}

export class TimeLocks {
    constructor(public config: any) {}
    
    static new(config: any): TimeLocks {
        return new TimeLocks(config);
    }
}

export class AuctionDetails {
    constructor(public config: any) {}
}

export class Immutables {
    constructor(public data: any) {}
    
    build(): any {
        // Return a properly structured object with all required fields
        return {
            chainId: this.data.chainId || 1,
            taker: this.data.taker || '0x0000000000000000000000000000000000000000',
            amount: this.data.amount || 0n,
            hashLock: this.data.hashLock || '0x0000000000000000000000000000000000000000000000000000000000000000',
            timeLocks: this.data.timeLocks || {},
            safetyDeposit: this.data.safetyDeposit || 0n,
            complement: this.data.complement || {},
            deployedAt: this.data.deployedAt || 0
        };
    }
    
    withComplement(complement: any): Immutables {
        return new Immutables({...this.data, complement});
    }
    
    withTaker(taker: Address): Immutables {
        return new Immutables({...this.data, taker: taker.toString()});
    }
    
    withDeployedAt(timestamp: number): Immutables {
        return new Immutables({...this.data, deployedAt: timestamp});
    }
    
    get safetyDeposit(): bigint {
        return this.data.safetyDeposit || 0n;
    }
    
    get timeLocks(): TimeLocks {
        return this.data.timeLocks || new TimeLocks({});
    }
}

export class CrossChainOrder {
    public salt: bigint;
    public maker: Address;
    public makingAmount: bigint;
    public takingAmount: bigint;
    public makerAsset: Address;
    public takerAsset: Address;
    public hashLock: HashLock;
    public timeLocks: TimeLocks;
    public srcChainId: number;
    public dstChainId: number;
    public srcSafetyDeposit: bigint;
    public dstSafetyDeposit: bigint;
    public auction: AuctionDetails;
    public whitelist: any[];
    public resolvingStartTime: bigint;
    public nonce: bigint;
    public allowPartialFills: boolean;
    public allowMultipleFills: boolean;
    public extension: any;
    public escrowExtension: any;

    constructor(
        escrowFactory: Address,
        orderData: any,
        crossChainData: any,
        auctionData: any,
        options: any
    ) {
        this.salt = orderData.salt;
        this.maker = orderData.maker;
        this.makingAmount = orderData.makingAmount;
        this.takingAmount = orderData.takingAmount;
        this.makerAsset = orderData.makerAsset;
        this.takerAsset = orderData.takerAsset;
        this.hashLock = crossChainData.hashLock;
        this.timeLocks = crossChainData.timeLocks;
        this.srcChainId = crossChainData.srcChainId;
        this.dstChainId = crossChainData.dstChainId;
        this.srcSafetyDeposit = crossChainData.srcSafetyDeposit;
        this.dstSafetyDeposit = crossChainData.dstSafetyDeposit;
        this.auction = auctionData.auction;
        this.whitelist = auctionData.whitelist;
        this.resolvingStartTime = auctionData.resolvingStartTime;
        this.nonce = options.nonce;
        this.allowPartialFills = options.allowPartialFills;
        this.allowMultipleFills = options.allowMultipleFills;
        this.extension = {};
        this.escrowExtension = {
            hashLockInfo: this.hashLock.value,
            srcSafetyDeposit: this.srcSafetyDeposit
        };
    }

    static new(
        escrowFactory: Address,
        orderData: any,
        crossChainData: any,
        auctionData: any,
        options: any
    ): CrossChainOrder {
        return new CrossChainOrder(escrowFactory, orderData, crossChainData, auctionData, options);
    }

    getOrderHash(chainId: number): string {
        // Mock implementation - return a hash based on order data
        const data = `${this.maker.toString()}-${this.makingAmount}-${this.takingAmount}-${chainId}`;
        return `0x${Buffer.from(data).toString('hex').substring(0, 64)}`;
    }

    getTypedData(chainId: number): any {
        // Mock implementation of EIP-712 typed data with valid values
        return {
            domain: {
                name: '1inch Cross-Chain Order',
                version: '1',
                chainId: chainId,
                verifyingContract: '0x111111125421ca6dc452d289314280a0f8842a65'
            },
            types: {
                Order: [
                    { name: 'salt', type: 'uint256' },
                    { name: 'maker', type: 'address' },
                    { name: 'makingAmount', type: 'uint256' },
                    { name: 'takingAmount', type: 'uint256' },
                    { name: 'makerAsset', type: 'address' },
                    { name: 'takerAsset', type: 'address' },
                    { name: 'hashLock', type: 'bytes32' },
                    { name: 'timeLocks', type: 'bytes' },
                    { name: 'srcChainId', type: 'uint256' },
                    { name: 'dstChainId', type: 'uint256' },
                    { name: 'srcSafetyDeposit', type: 'uint256' },
                    { name: 'dstSafetyDeposit', type: 'uint256' },
                    { name: 'auction', type: 'bytes' },
                    { name: 'whitelist', type: 'bytes' },
                    { name: 'resolvingStartTime', type: 'uint256' },
                    { name: 'nonce', type: 'uint256' },
                    { name: 'allowPartialFills', type: 'bool' },
                    { name: 'allowMultipleFills', type: 'bool' }
                ]
            },
            primaryType: 'Order',
            message: {
                salt: this.salt?.toString() || '0',
                maker: this.maker?.toString() || '0x0000000000000000000000000000000000000000',
                makingAmount: this.makingAmount?.toString() || '0',
                takingAmount: this.takingAmount?.toString() || '0',
                makerAsset: this.makerAsset?.toString() || '0x0000000000000000000000000000000000000000',
                takerAsset: this.takerAsset?.toString() || '0x0000000000000000000000000000000000000000',
                hashLock: this.hashLock?.value || '0x0000000000000000000000000000000000000000000000000000000000000000',
                timeLocks: '0x',
                srcChainId: this.srcChainId?.toString() || '1',
                dstChainId: this.dstChainId?.toString() || '1',
                srcSafetyDeposit: this.srcSafetyDeposit?.toString() || '0',
                dstSafetyDeposit: this.dstSafetyDeposit?.toString() || '0',
                auction: '0x',
                whitelist: '0x',
                resolvingStartTime: this.resolvingStartTime?.toString() || '0',
                nonce: this.nonce?.toString() || '0',
                allowPartialFills: this.allowPartialFills || false,
                allowMultipleFills: this.allowMultipleFills || false
            }
        };
    }

    toSrcImmutables(chainId: number, taker: Address, amount: bigint, hashLock: string): Immutables {
        return new Immutables({
            chainId,
            taker: taker.toString(),
            amount,
            hashLock,
            timeLocks: this.timeLocks,
            safetyDeposit: this.srcSafetyDeposit
        });
    }

    build(): any {
        return {
            salt: this.salt || 0n,
            maker: this.maker?.toString() || '0x0000000000000000000000000000000000000000',
            makingAmount: this.makingAmount || 0n,
            takingAmount: this.takingAmount || 0n,
            makerAsset: this.makerAsset?.toString() || '0x0000000000000000000000000000000000000000',
            takerAsset: this.takerAsset?.toString() || '0x0000000000000000000000000000000000000000',
            hashLock: this.hashLock?.value || '0x0000000000000000000000000000000000000000000000000000000000000000',
            timeLocks: this.timeLocks || {},
            srcChainId: this.srcChainId || 1,
            dstChainId: this.dstChainId || 1,
            srcSafetyDeposit: this.srcSafetyDeposit || 0n,
            dstSafetyDeposit: this.dstSafetyDeposit || 0n,
            auction: this.auction || {},
            whitelist: this.whitelist || [],
            resolvingStartTime: this.resolvingStartTime || 0n,
            nonce: this.nonce || 0n,
            allowPartialFills: this.allowPartialFills || false,
            allowMultipleFills: this.allowMultipleFills || false
        };
    }
}

export class TakerTraits {
    private extension: any;
    private amountMode: any;
    private amountThreshold: bigint;
    private interaction: any;

    static default(): TakerTraits {
        return new TakerTraits();
    }

    setExtension(extension: any): TakerTraits {
        this.extension = extension;
        return this;
    }

    setAmountMode(mode: any): TakerTraits {
        this.amountMode = mode;
        return this;
    }

    setAmountThreshold(threshold: bigint): TakerTraits {
        this.amountThreshold = threshold;
        return this;
    }

    setInteraction(interaction: any): TakerTraits {
        this.interaction = interaction;
        return this;
    }

    encode(): {args: any[], trait: any} {
        return {
            args: [],
            trait: this.extension || {}
        };
    }
}

export class AmountMode {
    static maker = 'maker';
}

export class EscrowFactory {
    constructor(public address: Address) {}

    getSrcEscrowAddress(event: any, implementation: string): string {
        // Mock implementation
        return `0x${Buffer.from(event.toString()).toString('hex').substring(0, 40)}`;
    }

    getDstEscrowAddress(event: any, complement: any, deployedAt: number, taker: Address, implementation: string): string {
        // Mock implementation
        return `0x${Buffer.from(taker.toString()).toString('hex').substring(0, 40)}`;
    }

    getMultipleFillInteraction(proof: string[], index: number, secretHash: string): any {
        // Mock implementation
        return { proof, index, secretHash };
    }
}

// Network enum for chain IDs
export const NetworkEnum = {
    ETHEREUM: 1,
    BINANCE: 56
} as const;

// Utility functions
export function randBigInt(max: bigint): bigint {
    return BigInt(Math.floor(Math.random() * Number(max)));
}

// Default export for the SDK
const Sdk = {
    Address,
    HashLock,
    TimeLocks,
    AuctionDetails,
    CrossChainOrder,
    TakerTraits,
    AmountMode,
    EscrowFactory,
    NetworkEnum,
    randBigInt,
    Immutables
};

export default Sdk; 