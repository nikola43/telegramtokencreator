import { ethers, network } from 'hardhat'
const util = require('../scripts/util');
const { parseEther } = ethers.utils;
const colors = require('colors');
import { expect } from 'chai'
import { formatEther } from 'ethers/lib/utils';
import { Contract } from 'ethers';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { updateABI } from '../scripts/util';


//available functions
describe("Token contract", async () => {

    function percentage(percent: any, total: any) {
        return (percent / 100) * total;
    }

    let tokenDeployed: Contract;
    let router: Contract;
    let uniToken: Contract;
    let pairContract: Contract;
    let deployer: SignerWithAddress;
    let bob: SignerWithAddress;
    let alice: SignerWithAddress;

    it("1. Get Signer", async () => {
        const signers = await ethers.getSigners();
        if (signers[0] !== undefined) {
            deployer = signers[0];
            console.log(`${colors.cyan('Deployer Address')}: ${colors.yellow(deployer?.address)}`)
        }
        if (signers[1] !== undefined) {
            bob = signers[1];
            console.log(`${colors.cyan('Bob Address')}: ${colors.yellow(bob?.address)}`)
        }
        if (signers[2] !== undefined) {
            alice = signers[2];
            console.log(`${colors.cyan('Alice Address')}: ${colors.yellow(alice?.address)}`)
        }
    });

    it("2. Deploy Contract", async () => {

        const tokenName = "Token";
        const tokenFactory = await ethers.getContractFactory(tokenName);
        tokenDeployed = await tokenFactory.deploy(
            "TKN",
            "Token",
            ethers.utils.parseEther("1000000000"),
            ["0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D", deployer.address],
            [0, 0]
        );
        await tokenDeployed.deployed();
        console.log(
            colors.cyan("Token Address: ") + colors.yellow(tokenDeployed.address)
        );
        await updateABI(tokenName);
    });
});

