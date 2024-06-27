const hre = require("hardhat");

async function main() {
  const [deployer] = await hre.ethers.getSigners();

  console.log("Deploying contracts with the account:", deployer.address);

  // You need to replace these with actual values
  const feeTokenAddress = "0xA61152baa58478e1089c000e84755f889aC3D442"; // Address of the ERC20 token used for fees
  const launchFee = hre.ethers.parseEther("500"); // Example: 500 tokens
  const uniswapFactoryAddress = "0x1F98431c8aD98523631AE4a59f267346ea31F984";
  const swapTokenAddress = "0xA61152baa58478e1089c000e84755f889aC3D442";

  // Deploy FeeManager
  const FeeManager = await hre.ethers.getContractFactory("FeeManager");
  const feeManager = await FeeManager.deploy(
    feeTokenAddress,
    launchFee,
    uniswapFactoryAddress,
    swapTokenAddress,
    deployer.address
  );

  await feeManager.waitForDeployment();

  console.log("FeeManager deployed to:", await feeManager.getAddress());

  // Deploy LabelFactory
  const LabelFactory = await hre.ethers.getContractFactory("LabelFactory");
  const labelFactory = await LabelFactory.deploy(await feeManager.getAddress());

  await labelFactory.waitForDeployment();

  console.log("LabelFactory deployed to:", await labelFactory.getAddress());

  // Get LabelOwnershipToken address
  const labelOwnershipTokenAddress = await labelFactory.labelOwnershipToken();
  console.log("LabelOwnershipToken deployed to:", labelOwnershipTokenAddress);

  // Verify contracts
  if (hre.network.name !== "hardhat" && hre.network.name !== "localhost") {
    console.log("Waiting for block confirmations...");
    
    await feeManager.deploymentTransaction().wait(5); // Wait for 5 block confirmations
    await labelFactory.deploymentTransaction().wait(5);

    console.log("Verifying contracts...");

    await hre.run("verify:verify", {
      address: await feeManager.getAddress(),
      constructorArguments: [
        feeTokenAddress,
        launchFee,
        uniswapFactoryAddress,
        swapTokenAddress,
        deployer.address
      ],
    });

    await hre.run("verify:verify", {
      address: await labelFactory.getAddress(),
      constructorArguments: [await feeManager.getAddress()],
    });

    await hre.run("verify:verify", {
      address: labelOwnershipTokenAddress,
      constructorArguments: [await labelFactory.getAddress()],
    });
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });