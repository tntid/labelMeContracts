const hre = require("hardhat");

async function main() {
  const [deployer] = await hre.ethers.getSigners();

  console.log("Deploying contracts with the account:", deployer.address);

  // You need to replace these with actual values
  const feeTokenAddress = "0xA61152baa58478e1089c000e84755f889aC3D442"; // Address of the ERC20 token used for fees
  const launchFee = hre.ethers.parseEther("500"); // Example: 100 tokens
  const uniswapFactoryAddress = "0x1F98431c8aD98523631AE4a59f267346ea31F984";

  const LabelFactory = await hre.ethers.getContractFactory("LabelFactory");
  const labelFactory = await LabelFactory.deploy(
    feeTokenAddress,
    launchFee,
    uniswapFactoryAddress,
    deployer.address
  );

  await labelFactory.waitForDeployment();

  console.log("LabelFactory deployed to:", await labelFactory.getAddress());
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });