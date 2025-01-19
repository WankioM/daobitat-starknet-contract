// scripts/deploy.ts
import { Account, Contract, json, RpcProvider } from "starknet";
import * as dotenv from "dotenv";
import fs from "fs";
import path from "path";

dotenv.config();

async function main() {
    // Initialize provider
    const provider = new RpcProvider({ 
        nodeUrl: process.env.STARKNET_RPC_URL || "https://alpha4.starknet.io" 
    });

    // Clean and format private key - remove '0x' prefix if present
    const privateKey = process.env.PRIVATE_KEY?.startsWith('0x') 
        ? process.env.PRIVATE_KEY.slice(2) 
        : process.env.PRIVATE_KEY;

    // Clean and format account address - ensure '0x' prefix
    const accountAddress = process.env.ACCOUNT_ADDRESS?.startsWith('0x')
        ? process.env.ACCOUNT_ADDRESS
        : `0x${process.env.ACCOUNT_ADDRESS}`;

    if (!privateKey || !accountAddress) {
        throw new Error("Missing private key or account address in .env file");
    }

    console.log("Initializing account...");
    console.log("Account address:", accountAddress);

    // Initialize account with cleaned values
    const account = new Account(
        provider,
        accountAddress,
        privateKey,
        '1' // Chain ID for testnet
    );

    try {
        // Load compiled contract
        const contractPath = path.join(__dirname, "../target/dev/daobitat_RentalContract.sierra.json");
        console.log("Looking for contract at:", contractPath);

        if (!fs.existsSync(contractPath)) {
            throw new Error(`Contract file not found at ${contractPath}. Did you run 'scarb build'?`);
        }

        const compiledContract = json.parse(
            fs.readFileSync(contractPath).toString("utf-8")
        );

        // Constructor arguments
        const constructorCalldata = [
            accountAddress,    // admin address
            "250"              // platform fee (2.5%)
        ];

        // Declare contract
        console.log("Declaring contract...");
        const declareResponse = await account.declare({
            contract: compiledContract,
            classHash: compiledContract.class_hash
        });
        
        console.log("Waiting for declaration transaction...");
        await provider.waitForTransaction(declareResponse.transaction_hash);
        console.log("Contract declared with class hash:", declareResponse.class_hash);

        // Deploy contract
        console.log("Deploying contract...");
        const deployResponse = await account.deploy({
            classHash: declareResponse.class_hash,
            constructorCalldata
        });

        console.log("Waiting for deployment transaction...");
        await provider.waitForTransaction(deployResponse.transaction_hash);
        
        console.log("Contract deployed successfully!");
        console.log("Contract address:", deployResponse.contract_address);
        
        // Save deployment info
        const deploymentInfo = {
            contractAddress: deployResponse.contract_address,
            classHash: declareResponse.class_hash,
            transactionHash: deployResponse.transaction_hash,
            network: process.env.STARKNET_NETWORK || "testnet",
            timestamp: new Date().toISOString()
        };

        // Save to file
        const deploymentPath = path.join(__dirname, "../deployment-info.json");
        fs.writeFileSync(
            deploymentPath,
            JSON.stringify(deploymentInfo, null, 2)
        );

        console.log(`Deployment info saved to ${deploymentPath}`);

    } catch (error) {
        console.error("Deployment failed:", error);
        process.exit(1);
    }
}

main();