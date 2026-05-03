import docsJson from '../../nav.json'

export type NavItem = {
  title: string
  href: string
}

export type NavGroup = {
  id: string
  title: string
  items: NavItem[]
}

export const navGroups: NavGroup[] = (docsJson as any).groups.map((group: any) => ({
  id: group.id,
  title: group.title,
  items: group.items.map((item: any) => ({
    title: item.title,
    href: '/docs/' + item.id,
  })),
}))
