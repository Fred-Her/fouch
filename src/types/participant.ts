export interface Participant {
  id: string;
  eventId: string;
  displayName: string;
  /** ISO 3166-1 alpha-2. */
  countryCode: string;
  countryName: string;
  sortOrder: number;
  isActive: boolean;
}