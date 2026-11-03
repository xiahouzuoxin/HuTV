import { test, expect } from '@playwright/test';
import { defaults } from '../shared/defaults';
const fixture = {
  class: [{ type_id: 1, type_name: '电影' }],
  pagecount: 2,
  list: [
    {
      vod_id: '1',
      vod_name: '测试电影',
      vod_pic: '',
      vod_year: 2026,
      type_name: '剧情',
      vod_content: '这是一段影片介绍',
      vod_score: 8.2,
      vod_douban_score: 7.8,
      vod_play_from: '线路A',
      vod_play_url:
        '第1集$https://storage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4#第2集$https://storage.googleapis.com/gtv-videos-bucket/sample/Sintel.mp4',
    },
  ],
};
test.beforeEach(async ({ page }) => {
  // Keep fixtures independent of upstream network/CORS; auto then exercises the proxy.
  await page.route(
    (url) => defaults.some((source) => new URL(source.url).origin === url.origin),
    (route) => route.abort('failed'),
  );
  await page.route('**/api/discovery**', (route) =>
    route.fulfill({
      contentType: 'application/json',
      body: JSON.stringify({
        subjects: [
          {
            id: '1',
            title: '推荐影片',
            rate: '8.6',
            cover: 'https://img9.doubanio.com/view/photo/s_ratio_poster/public/p1234567890.jpg',
          },
          { id: '2', title: '另一部推荐', rate: '7.4', cover: '' },
        ],
      }),
    }),
  );
  await page.route('**/api/douban-cover**', (route) =>
    route.fulfill({
      contentType: 'image/png',
      body: Buffer.from(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==',
        'base64',
      ),
    }),
  );
  await page.route('**/api/fetch', async (route) => {
    const url = route.request().postDataJSON()?.url ?? '';
    if (url.includes('api.php'))
      return route.fulfill({ contentType: 'text/plain', body: JSON.stringify(fixture) });
    if (url.includes('m3u'))
      return route.fulfill({
        contentType: 'text/plain',
        body: '#EXTM3U\n#EXTINF:-1 group-title="演示",演示频道\nhttps://storage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
      });
    return route.fulfill({
      status: 403,
      contentType: 'application/json',
      body: '{"error":"未允许的域名"}',
    });
  });
});
test('desktop browsing, subscriptions, search and metadata', async ({ page }) => {
  await page.goto('/');
  await expect(page.getByRole('heading', { name: '今天，想看点什么？' })).toBeVisible();
  await expect(page.getByRole('button', { name: '查看 推荐影片' })).toBeVisible();
  await page.getByRole('button', { name: '我的订阅' }).click();
  await page.getByRole('button', { name: '编辑 暴风资源' }).click();
  await page.getByLabel('订阅名称', { exact: true }).fill('暴风测试');
  await page.getByRole('button', { name: '保存修改' }).click();
  await expect(page.getByRole('heading', { name: '暴风测试' })).toBeVisible();
  await page.getByRole('button', { name: '发现片库' }).click();
  await page.getByLabel('搜索影片').fill('测试');
  await page.getByLabel('搜索影片').press('Enter');
  await expect(page.getByRole('button', { name: '查看 测试电影' }).first()).toBeVisible();
  await page.getByRole('button', { name: '查看 测试电影' }).first().click();
  await expect(page.getByRole('heading', { name: '测试电影', exact: true })).toBeVisible();
  await expect(page.getByText('豆瓣评分（源提供） 7.8')).toBeVisible();
  await expect(page.getByText('这是一段影片介绍')).toBeVisible();
  await expect(page.getByRole('button', { name: '第1集', exact: true })).toBeVisible();
  await page.screenshot({ path: 'test-results/screenshots/hutv-web-detail.png', fullPage: true });
});
test('playback persists history and lock blocks controls', async ({ page }) => {
  await page.goto('/');
  await page.getByLabel('搜索影片').fill('测试');
  await page.getByLabel('搜索影片').press('Enter');
  await page.getByRole('button', { name: '查看 测试电影' }).first().click();
  await page.getByRole('button', { name: '开始观看' }).click();
  await page.locator('video').evaluate((v) => {
    v.dispatchEvent(new Event('loadedmetadata'));
    v.dispatchEvent(new Event('playing'));
  });
  await page.getByRole('button', { name: '锁定播放器', exact: true }).click();
  await expect(page.getByRole('button', { name: '解锁播放器', exact: true })).toBeVisible();
  await expect(page.getByRole('button', { name: '暂停播放', exact: true })).toHaveCount(0);
  await page.locator('.touch-shield').dblclick();
  await expect(page.getByRole('button', { name: '解锁播放器', exact: true })).toBeVisible();
  await page.getByRole('button', { name: '解锁播放器', exact: true }).click();
  await expect(page.getByRole('button', { name: '重新加载', exact: true })).toBeVisible();
  await page.locator('video').evaluate((v) => {
    v.dispatchEvent(new Event('timeupdate'));
    v.dispatchEvent(new Event('pause'));
  });
  await page.getByRole('button', { name: '返回搜索结果' }).click();
  await page.getByRole('button', { name: '观看历史', exact: true }).click();
  await expect(page.getByRole('button', { name: '查看 测试电影' })).toBeVisible();
  await page.reload();
  await page.getByRole('button', { name: '观看历史', exact: true }).click();
  await expect(page.getByRole('button', { name: '查看 测试电影' })).toBeVisible();
});
test('mobile layout and JSON subscription import', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/');
  await page.getByRole('button', { name: '打开导航' }).click();
  await page.getByRole('button', { name: '我的订阅', exact: false }).click();
  await page.getByRole('button', { name: '添加订阅' }).last().click();
  await page.getByRole('button', { name: 'JSON 批量导入' }).click();
  await page
    .getByLabel('JSON 内容或在线列表链接')
    .fill('[{"name":"自定义测试源","api":"https://example.com/api","kind":"cms"}]');
  await page.getByRole('button', { name: '预览订阅' }).click();
  await expect(page.getByText('识别到 1 个订阅', { exact: false })).toBeVisible();
  await page.getByRole('button', { name: '确认导入' }).click();
  await expect(page.getByRole('heading', { name: '自定义测试源' })).toBeVisible();
  expect(
    await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth),
  ).toBeTruthy();
  await page.screenshot({ path: 'test-results/screenshots/hutv-web-mobile.png', fullPage: true });
});
test('discovery homepage has no errors and fits desktop', async ({ page }) => {
  const errors: string[] = [];
  page.on('pageerror', (e) => errors.push(e.message));
  await page.goto('/');
  await expect(page.getByRole('button', { name: '查看 另一部推荐' })).toBeVisible();
  await page.screenshot({ path: 'test-results/screenshots/hutv-web-home.png', fullPage: true });
  expect(errors).toEqual([]);
  expect(
    await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth),
  ).toBeTruthy();
});
test('next episode uses the loaded queue without another detail request', async ({ page }) => {
  let details = 0;
  page.on('request', (r) => {
    if (r.url().includes('/api/fetch') && r.postDataJSON()?.url.includes('ids=')) details++;
  });
  await page.goto('/');
  await page.getByLabel('搜索影片').fill('测试');
  await page.getByLabel('搜索影片').press('Enter');
  await page.getByRole('button', { name: '查看 测试电影' }).first().click();
  await page.getByRole('button', { name: '第1集', exact: true }).click();
  const before = details;
  await page.getByRole('button', { name: '下一集', exact: true }).click();
  await expect(page.getByRole('button', { name: '第2集', exact: true })).toHaveClass(/active/);
  expect(details).toBe(before);
});

test('Douban categories load on demand, reuse one-day cache and search by title', async ({
  page,
}) => {
  const calls: string[] = [];
  page.on('request', (r) => {
    if (r.url().includes('/api/discovery?')) calls.push(r.url());
  });
  await page.goto('/');
  await expect(page.getByRole('button', { name: '查看 推荐影片' })).toBeVisible();
  expect(calls).toHaveLength(1);
  expect(new URL(calls[0]).searchParams.get('tag')).toBe('热门');
  await page.getByRole('button', { name: '最新', exact: true }).click();
  await expect.poll(() => calls.length).toBe(2);
  await expect(page.getByRole('button', { name: '查看 推荐影片' })).toBeVisible();
  await page.getByRole('button', { name: '热门', exact: true }).click();
  await expect(page.getByRole('button', { name: '查看 推荐影片' })).toBeVisible();
  expect(calls).toHaveLength(2);
  await page.reload();
  await expect(page.getByRole('button', { name: '查看 推荐影片' })).toBeVisible();
  expect(calls).toHaveLength(2);
  await page.getByRole('button', { name: '剧集', exact: true }).click();
  await expect.poll(() => calls.length).toBe(3);
  expect(new URL(calls[2]).searchParams.get('type')).toBe('tv');
  await page.getByRole('button', { name: '美剧', exact: true }).click();
  await expect.poll(() => calls.length).toBe(4);
  await expect(page.getByRole('button', { name: '刷新豆瓣推荐' })).toBeEnabled();
  await page.getByRole('button', { name: '刷新豆瓣推荐' }).click();
  await expect.poll(() => calls.length).toBe(5);
  expect(new URL(calls[4]).searchParams.get('refresh')).toBe('1');
  await page.getByRole('button', { name: '查看 推荐影片' }).click();
  await expect(page.getByLabel('搜索影片')).toHaveValue('推荐影片');
  await expect(page.getByRole('button', { name: '查看 测试电影' }).first()).toBeVisible();
});
test('refresh errors preserve cached recommendations and native source browsing still works', async ({
  page,
}) => {
  await page.goto('/');
  await expect(page.getByRole('button', { name: '查看 推荐影片' })).toBeVisible();
  await page.route('**/api/discovery**', (route) =>
    route.fulfill({
      status: 502,
      contentType: 'application/json',
      body: JSON.stringify({ error: '暂时无法获取推荐' }),
    }),
  );
  await page.getByRole('button', { name: '刷新豆瓣推荐' }).click();
  await expect(page.getByRole('alert')).toContainText('当前保留上次的推荐');
  await expect(page.getByRole('button', { name: '查看 推荐影片' })).toBeVisible();
  await page.getByLabel('选择点播源').selectOption('cms-0');
  await expect(page.getByRole('button', { name: '查看 测试电影' })).toBeVisible();
  await expect(page.getByRole('button', { name: '刷新片库', exact: true })).toBeVisible();
});

test('request mode is editable and survives reload', async ({ page }) => {
  await page.goto('/');
  await page.getByRole('button', { name: '我的订阅', exact: false }).click();
  await page.getByRole('button', { name: '编辑 暴风资源' }).click();
  await expect(page.getByLabel('请求模式', { exact: true })).toHaveValue('auto');
  await page.getByLabel('请求模式', { exact: true }).selectOption('proxy');
  await page.getByRole('button', { name: '保存修改' }).click();
  await expect(page.getByRole('dialog')).toBeHidden();
  await page.reload();
  await page.getByRole('button', { name: '我的订阅', exact: false }).click();
  await page.getByRole('button', { name: '编辑 暴风资源' }).click();
  await expect(page.getByLabel('请求模式', { exact: true })).toHaveValue('proxy');
});

test.describe('touch phone', () => {
  test.use({ isMobile: true, hasTouch: true });
  test('phone playback fits narrow portrait and landscape and fullscreen exits cleanly', async ({
    page,
  }) => {
    await page.setViewportSize({ width: 320, height: 740 });
    await page.goto('/');
    await page.getByLabel('搜索影片').fill('测试');
    await page.getByLabel('搜索影片').press('Enter');
    await page.getByRole('button', { name: '查看 测试电影' }).first().click();
    await page.getByRole('button', { name: '第1集', exact: true }).click();
    const player = page.locator('.player');
    await expect(page.getByRole('button', { name: '全屏播放', exact: true })).toBeVisible();
    for (const width of [320, 390]) {
      await page.setViewportSize({ width, height: 844 });
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(
        true,
      );
      const bounds = await player.boundingBox();
      const control = await page
        .getByRole('button', { name: '全屏播放', exact: true })
        .boundingBox();
      expect(control!.x + control!.width).toBeLessThanOrEqual(bounds!.x + bounds!.width);
    }
    await page.screenshot({
      path: 'test-results/screenshots/hutv-web-mobile-player.png',
      fullPage: true,
    });
    await page.getByRole('button', { name: '全屏播放', exact: true }).click();
    await expect(player).toHaveAttribute('data-fullscreen', 'element');
    expect(
      await page.evaluate(() => document.fullscreenElement?.classList.contains('player')),
    ).toBe(true);
    await page.getByRole('button', { name: '退出全屏', exact: true }).click();
    await expect(player).toHaveAttribute('data-fullscreen', 'inline');
    // Simulate an iPhone browser exposing video-only fullscreen.
    await player.evaluate((box) => {
      Object.defineProperty(box, 'requestFullscreen', { configurable: true, value: undefined });
      const video = box.querySelector('video')!;
      Object.assign(video, {
        webkitEnterFullscreen: () => video.dispatchEvent(new Event('webkitbeginfullscreen')),
      });
    });
    await page.getByRole('button', { name: '全屏播放', exact: true }).click();
    await expect(player).toHaveAttribute('data-fullscreen', 'video');
    await page.locator('video').dispatchEvent('webkitendfullscreen');
    await expect(player).toHaveAttribute('data-fullscreen', 'inline');
    await expect(player).not.toHaveClass(/fullscreen/);
    await page.setViewportSize({ width: 844, height: 390 });
    await expect(page.getByRole('button', { name: '打开导航', exact: true })).toBeVisible();
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(
      true,
    );
    const control = await page.getByRole('button', { name: '全屏播放', exact: true }).boundingBox();
    expect(control!.y + control!.height).toBeLessThanOrEqual(390);
    await page.screenshot({ path: 'test-results/screenshots/hutv-web-mobile-landscape.png' });
  });
});
