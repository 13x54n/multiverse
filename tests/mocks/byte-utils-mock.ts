// Mock implementation of @1inch/byte-utils
// This replaces the private package with basic functionality for testing

export const UINT_40_MAX = 2n ** 40n - 1n;

export function uint8ArrayToHex(bytes: Uint8Array): string {
    return '0x' + Array.from(bytes)
        .map(b => b.toString(16).padStart(2, '0'))
        .join('');
} 