import {z} from 'zod';

export const targetSchema = z.object({
  minter: z.string(),
  hub: z.string(),
  assetId: z.number().int().nonnegative(),
});
export type Target = z.infer<typeof targetSchema>;

export const networkSchema = z.object({
  chainName: z.string(),
  targets: z.array(targetSchema),
});
export type NetworkConfig = z.infer<typeof networkSchema>;

export const configSchema = z.object({
  schedule: z.string(),
  evms: z.array(networkSchema),
});
export type Config = z.infer<typeof configSchema>;
