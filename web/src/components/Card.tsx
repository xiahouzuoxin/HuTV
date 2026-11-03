import { useState } from 'react';
import { Play, Film, Star } from 'lucide-react';
import type { Movie } from '../../shared/types';
export function Card({
  movie,
  onClick,
  foot,
  onRemove,
}: {
  movie: Movie;
  onClick: () => void;
  foot?: string;
  onRemove?: () => void;
}) {
  const [broken, setBroken] = useState(false);
  return (
    <article className="movie-card">
      <button className="poster-button" onClick={onClick} aria-label={'查看 ' + movie.title}>
        {movie.poster && !broken ? (
          <img
            src={movie.poster}
            alt={movie.title}
            loading="lazy"
            referrerPolicy="no-referrer"
            onError={() => setBroken(true)}
          />
        ) : (
          <div className="poster-placeholder">
            <Film size={34} />
            <span>{movie.title}</span>
          </div>
        )}
        <div className="poster-shade" />
        <span className="poster-play">
          <Play size={23} fill="currentColor" />
        </span>
        {movie.rating && (
          <span className={'rating ' + movie.rating.kind}>
            <Star size={11} />
            {movie.rating.kind === 'douban' ? '豆瓣 ' : ''}
            {movie.rating.value.toFixed(1)}
          </span>
        )}
        {movie.remarks && <span className="poster-note">{movie.remarks}</span>}
      </button>
      <div className="card-copy">
        <button className="movie-title" onClick={onClick}>
          {movie.title}
        </button>
        <p>
          {foot ||
            [movie.year, movie.area, movie.category].filter(Boolean).join(' · ') ||
            '点击查看详情'}
        </p>
        {onRemove && (
          <button className="text-button subtle" onClick={onRemove}>
            移除记录
          </button>
        )}
      </div>
    </article>
  );
}
