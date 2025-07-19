import { app, InvocationContext } from "@azure/functions";
import { CosmosClient } from "@azure/cosmos";

export async function blobTrigger(blob: unknown, context: InvocationContext): Promise<void> {
    context.log('Processing blob:', context.triggerMetadata?.name);

    try {
        // Convert blob to string and parse JSON
        const blobString = (blob as Buffer).toString();
        const data = JSON.parse(blobString);
        
        // Connect to Cosmos DB using environment variables
        const cosmosClient = new CosmosClient({
            endpoint: process.env.COSMOSDB_ENDPOINT!,
            key: process.env.COSMOSDB_KEY!
        });
        const database = cosmosClient.database("pipeline-db");
        const container = database.container("data");

        // Handle both single objects and arrays
        const items = Array.isArray(data) ? data : [data];
        
        // Save each item to Cosmos DB
        for (const item of items) {
            await container.items.upsert(item);
            context.log(`Saved item with id: ${item.id}`);
        }
        
        context.log(`Data saved to Cosmos DB - ${items.length} items processed`);
    } catch (error) {
        context.error("Error processing blob:", error);
        throw error;
    }
}

app.storageBlob('blobTrigger', {
    path: 'data/{name}',
    connection: 'AzureWebJobsStorage',
    handler: blobTrigger,
});