import { HttpRequest, InvocationContext } from "@azure/functions";
import { CosmosClient } from "@azure/cosmos";

const blobTrigger = async function (req: HttpRequest, inputBlob: Buffer, context: InvocationContext): Promise<void> {
    const blobName = context.extraInputs.get('inputBlob');
    context.log(`Processing blob: ${blobName}`);

    try {
        const data = JSON.parse(inputBlob.toString());
        const cosmosClient = new CosmosClient({
            endpoint: process.env.COSMOSDB_ENDPOINT,
            key: process.env.COSMOSDB_KEY
        });
        const database = cosmosClient.database("pipeline-db");
        const container = database.container("data");
        await container.items.upsert(data);
        context.log("Data saved to Cosmos DB");
    } catch (error) {
        context.error("Error processing blob:", error);
        throw error;
    }
};

export default blobTrigger;