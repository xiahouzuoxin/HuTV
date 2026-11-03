export type SourceKind = 'cms' | 'live';
export interface Source {
  id: string;
  name: string;
  url: string;
  kind: SourceKind;
  enabled: boolean;
}
export interface Rating {
  value: number;
  kind: 'douban' | 'source';
}
export interface Episode {
  id: string;
  name: string;
  url: string;
  line: string;
}
export interface Movie {
  id: string;
  sourceId: string;
  title: string;
  poster: string;
  remarks: string;
  year: string;
  area: string;
  category: string;
  rating?: Rating;
  summary: string;
  actors: string;
  director: string;
  language: string;
  episodes: Episode[];
}
export interface Category {
  id: string;
  name: string;
}
export interface Channel {
  id: string;
  name: string;
  url: string;
  logo: string;
  group: string;
}
export interface HistoryEntry {
  id: string;
  movie: Movie;
  source: Source;
  episodeId: string;
  position: number;
  duration: number;
  updatedAt: number;
  live?: boolean;
}
export interface Settings {
  concurrency: number;
  rate: number;
  autoNext: boolean;
  buffer: number;
}
export interface Library {
  sources: Source[];
  history: HistoryEntry[];
  searches: string[];
  openings: Record<string, number>;
  settings: Settings;
}
export interface SearchResult {
  source: Source;
  items: Movie[];
  status: 'loading' | 'done' | 'error';
  error?: string;
}
