/*
 * GKI SUSFS feature backport for kernel 4.14
 *
 * Adds SUS_MAP (full maps entry spoofing), SUS_PROC_FD_LINK
 * (proc fd link hiding), and SUS_MEMFD (memfd blocking) features
 * from the SUSFS GKI branch to kernel 4.14.
 *
 * Appended to the base 4.14 susfs.c during CI build.
 * All functions are gated by CONFIG_KSU_SUSFS_SUS_MAP,
 * CONFIG_KSU_SUSFS_SUS_PROC_FD_LINK, CONFIG_KSU_SUSFS_SUS_MEMFD.
 */

/***********/
/* SUS_MAP */
/***********/
#ifdef CONFIG_KSU_SUSFS_SUS_MAP

#define SUSFS_MAX_LEN_PATHNAME 256

struct st_susfs_sus_maps {
	bool                    is_statically;
	int                     compare_mode;
	bool                    is_isolated_entry;
	bool                    is_file;
	unsigned long           prev_target_ino;
	unsigned long           next_target_ino;
	char                    target_pathname[SUSFS_MAX_LEN_PATHNAME];
	unsigned long           target_ino;
	unsigned long           target_dev;
	unsigned long long      target_pgoff;
	unsigned long           target_prot;
	unsigned long           target_addr_size;
	char                    spoofed_pathname[SUSFS_MAX_LEN_PATHNAME];
	unsigned long           spoofed_ino;
	unsigned long           spoofed_dev;
	unsigned long long      spoofed_pgoff;
	unsigned long           spoofed_prot;
	bool                    need_to_spoof_pathname;
	bool                    need_to_spoof_ino;
	bool                    need_to_spoof_dev;
	bool                    need_to_spoof_pgoff;
	bool                    need_to_spoof_prot;
};

struct st_susfs_sus_maps_list {
	struct list_head                        list;
	struct st_susfs_sus_maps                info;
};

static LIST_HEAD(LH_SUS_MAPS_SPOOFER);

int susfs_is_sus_maps_list_empty(void)
{
	return list_empty(&LH_SUS_MAPS_SPOOFER);
}
EXPORT_SYMBOL(susfs_is_sus_maps_list_empty);

int susfs_add_sus_maps(struct st_susfs_sus_maps __user *user_info)
{
	struct st_susfs_sus_maps_list *cursor, *temp;
	struct st_susfs_sus_maps_list *new_list = NULL;
	struct st_susfs_sus_maps info;
	int list_count = 0;

	if (copy_from_user(&info, user_info, sizeof(struct st_susfs_sus_maps))) {
		SUSFS_LOGE("failed copying from userspace\n");
		return 1;
	}

	/* dev decode for non-GKI */
	info.target_dev = old_decode_dev(info.target_dev);

	list_for_each_entry_safe(cursor, temp, &LH_SUS_MAPS_SPOOFER, list) {
		if (cursor->info.is_statically == info.is_statically && !info.is_statically) {
			if (cursor->info.target_ino == info.target_ino) {
				SUSFS_LOGE("is_statically: '%d', target_ino: '%lu', is already created in LH_SUS_MAPS_SPOOFER\n",
					info.is_statically, info.target_ino);
				return 1;
			}
		} else if (cursor->info.is_statically == info.is_statically && info.is_statically) {
			if (cursor->info.compare_mode == info.compare_mode && info.compare_mode == 1) {
				if (cursor->info.target_ino == info.target_ino) {
					SUSFS_LOGE("is_statically: '%d', compare_mode: '%d', target_ino: '%lu', is already created in LH_SUS_MAPS_SPOOFER\n",
						info.is_statically, info.compare_mode, info.target_ino);
					return 1;
				}
			} else if (cursor->info.compare_mode == info.compare_mode && info.compare_mode == 2) {
				if (cursor->info.target_ino == info.target_ino &&
				    cursor->info.target_dev == info.target_dev &&
				    cursor->info.target_addr_size == info.target_addr_size &&
				    cursor->info.target_pgoff == info.target_pgoff &&
				    !strcmp(cursor->info.target_pathname, info.target_pathname)) {
					SUSFS_LOGE("is_statically: '%d', compare_mode: '%d', target_ino: '%lu', target_pathname: '%s', is already created in LH_SUS_MAPS_SPOOFER\n",
						info.is_statically, info.compare_mode, info.target_ino, info.target_pathname);
					return 1;
				}
			}
		}
		list_count++;
	}

	new_list = kmalloc(sizeof(struct st_susfs_sus_maps_list), GFP_KERNEL);
	if (!new_list) {
		SUSFS_LOGE("no enough memory\n");
		return 1;
	}

	memcpy(&new_list->info, &info, sizeof(struct st_susfs_sus_maps));
	new_list->info.spoofed_dev = old_decode_dev(new_list->info.spoofed_dev);
	INIT_LIST_HEAD(&new_list->list);
	spin_lock(&susfs_spin_lock);
	list_add_tail(&new_list->list, &LH_SUS_MAPS_SPOOFER);
	spin_unlock(&susfs_spin_lock);

	SUSFS_LOGI("is_statically: '%d', compare_mode: '%d', is_isolated_entry: '%d', is_file: '%d', "
		"prev_target_ino: '%lu', next_target_ino: '%lu', target_ino: '%lu', target_dev: '0x%x', "
		"target_pgoff: '0x%llx', target_prot: '0x%lx', target_addr_size: '0x%lx', "
		"spoofed_pathname: '%s', spoofed_ino: '%lu', spoofed_dev: '0x%x', "
		"spoofed_pgoff: '0x%llx', spoofed_prot: '0x%lx', "
		"is successfully added to LH_SUS_MAPS_SPOOFER\n",
		new_list->info.is_statically, new_list->info.compare_mode,
		new_list->info.is_isolated_entry, new_list->info.is_file,
		new_list->info.prev_target_ino, new_list->info.next_target_ino,
		new_list->info.target_ino, new_list->info.target_dev,
		new_list->info.target_pgoff, new_list->info.target_prot,
		new_list->info.target_addr_size, new_list->info.spoofed_pathname,
		new_list->info.spoofed_ino, new_list->info.spoofed_dev,
		new_list->info.spoofed_pgoff, new_list->info.spoofed_prot);

	return 0;
}
EXPORT_SYMBOL(susfs_add_sus_maps);

int susfs_update_sus_maps(struct st_susfs_sus_maps __user *user_info)
{
	struct st_susfs_sus_maps_list *cursor, *temp;
	struct st_susfs_sus_maps info;

	if (copy_from_user(&info, user_info, sizeof(struct st_susfs_sus_maps))) {
		SUSFS_LOGE("failed copying from userspace\n");
		return 1;
	}

	list_for_each_entry_safe(cursor, temp, &LH_SUS_MAPS_SPOOFER, list) {
		if (cursor->info.is_statically == info.is_statically && !info.is_statically) {
			if (unlikely(!strcmp(info.target_pathname, cursor->info.target_pathname))) {
				SUSFS_LOGI("updating target_ino from '%lu' to '%lu' for pathname: '%s' in LH_SUS_MAPS_SPOOFER\n",
					cursor->info.target_ino, info.target_ino, info.target_pathname);
				cursor->info.target_ino = info.target_ino;
				return 0;
			}
		}
	}

	SUSFS_LOGE("target_pathname: '%s' is not found in LH_SUS_MAPS_SPOOFER\n", info.target_pathname);
	return 1;
}
EXPORT_SYMBOL(susfs_update_sus_maps);

/* Called from show_map_vma in fs/proc/task_mmu.c
 * Returns:
 *   0 - no spoofing, use original values
 *   1 - spoof ino/dev/pgoff/prot only (don't change pathname)
 *   2 - full spoofing with pathname override
 */
int susfs_sus_maps(unsigned long ino, unsigned long addr_size,
		   unsigned long *spoofed_ino, dev_t *spoofed_dev,
		   int *spoofed_flags, unsigned long long *spoofed_pgoff,
		   struct vm_area_struct *vma, char *out_name)
{
	struct st_susfs_sus_maps_list *cursor;
	struct file *vma_file = vma->vm_file;
	struct dentry *vma_dentry;
	struct inode *vma_inode;
	int ret = 0;

	if (unlikely(!current->mm))
		return 0;

	list_for_each_entry(cursor, &LH_SUS_MAPS_SPOOFER, list) {
		if (cursor->info.is_statically)
			continue;

		/* Mode 1: match by inode */
		if (cursor->info.compare_mode == 1) {
			if (cursor->info.target_ino == ino) {
				if (cursor->info.need_to_spoof_ino)
					*spoofed_ino = cursor->info.spoofed_ino;
				if (cursor->info.need_to_spoof_dev)
					*spoofed_dev = cursor->info.spoofed_dev;
				if (cursor->info.need_to_spoof_pgoff)
					*spoofed_pgoff = cursor->info.spoofed_pgoff;
				if (cursor->info.need_to_spoof_prot)
					*spoofed_flags = cursor->info.spoofed_prot;
				if (cursor->info.need_to_spoof_pathname) {
					strncpy(out_name, cursor->info.spoofed_pathname, SUSFS_MAX_LEN_PATHNAME - 1);
					out_name[SUSFS_MAX_LEN_PATHNAME - 1] = '\0';
					ret = 2;
				} else {
					ret = 1;
				}
				goto out;
			}
		}

		/* Mode 2: match by ino+dev+pgoff+pathname+size */
		if (cursor->info.compare_mode == 2 && vma_file) {
			vma_dentry = vma_file->f_path.dentry;
			vma_inode = file_inode(vma_file);
			if (cursor->info.target_ino == vma_inode->i_ino &&
			    cursor->info.target_dev == vma_inode->i_sb->s_dev &&
			    cursor->info.target_addr_size == addr_size &&
			    cursor->info.target_pgoff == vma->vm_pgoff) {
				if (cursor->info.need_to_spoof_ino)
					*spoofed_ino = cursor->info.spoofed_ino;
				if (cursor->info.need_to_spoof_dev)
					*spoofed_dev = cursor->info.spoofed_dev;
				if (cursor->info.need_to_spoof_pgoff)
					*spoofed_pgoff = cursor->info.spoofed_pgoff;
				if (cursor->info.need_to_spoof_prot)
					*spoofed_flags = cursor->info.spoofed_prot;
				if (cursor->info.need_to_spoof_pathname) {
					strncpy(out_name, cursor->info.spoofed_pathname, SUSFS_MAX_LEN_PATHNAME - 1);
					out_name[SUSFS_MAX_LEN_PATHNAME - 1] = '\0';
					ret = 2;
				} else {
					ret = 1;
				}
				goto out;
			}
		}
	}

	/* Check isolated entries */
	list_for_each_entry(cursor, &LH_SUS_MAPS_SPOOFER, list) {
		if (!cursor->info.is_statically)
			continue;
		if (!cursor->info.is_isolated_entry)
			continue;

		if (cursor->info.compare_mode == 1 && cursor->info.target_ino == ino) {
			*spoofed_flags = cursor->info.spoofed_prot;
			ret = 1;
			goto out;
		}
	}

out:
	return ret;
}
EXPORT_SYMBOL(susfs_sus_maps);

/* Called from map_files instantiation path */
int susfs_sus_map_files_instantiate(struct dentry *dentry, struct task_struct *task)
{
	/* Stub: GKI version has full implementation, minimal for 4.14 */
	return 0;
}
EXPORT_SYMBOL(susfs_sus_map_files_instantiate);

/* Called from map_files readlink path */
void susfs_sus_map_files_readlink(unsigned long ino, char *pathname)
{
	/* Stub - could be extended */
}
EXPORT_SYMBOL(susfs_sus_map_files_readlink);

#endif /* CONFIG_KSU_SUSFS_SUS_MAP */

/*******************/
/* SUS_PROC_FD_LINK */
/*******************/
#ifdef CONFIG_KSU_SUSFS_SUS_PROC_FD_LINK

#define SUSFS_MAX_LEN_PATHNAME 256

struct st_susfs_sus_proc_fd_link {
	char                    target_link_name[SUSFS_MAX_LEN_PATHNAME];
	char                    spoofed_link_name[SUSFS_MAX_LEN_PATHNAME];
};

struct st_susfs_sus_proc_fd_link_list {
	struct list_head                        list;
	struct st_susfs_sus_proc_fd_link        info;
};

static LIST_HEAD(LH_SUS_PROC_FD_LINK);

bool susfs_is_sus_proc_fd_link_list_empty(void)
{
	return list_empty(&LH_SUS_PROC_FD_LINK);
}
EXPORT_SYMBOL(susfs_is_sus_proc_fd_link_list_empty);

int susfs_add_sus_proc_fd_link(struct st_susfs_sus_proc_fd_link __user *user_info)
{
	struct st_susfs_sus_proc_fd_link_list *cursor, *temp;
	struct st_susfs_sus_proc_fd_link_list *new_list = NULL;
	struct st_susfs_sus_proc_fd_link info;

	if (copy_from_user(&info, user_info, sizeof(struct st_susfs_sus_proc_fd_link))) {
		SUSFS_LOGE("failed copying from userspace\n");
		return 1;
	}

	list_for_each_entry_safe(cursor, temp, &LH_SUS_PROC_FD_LINK, list) {
		if (!strcmp(info.target_link_name, cursor->info.target_link_name)) {
			SUSFS_LOGE("link name: '%s' is already in LH_SUS_PROC_FD_LINK\n", info.target_link_name);
			return 1;
		}
	}

	new_list = kmalloc(sizeof(struct st_susfs_sus_proc_fd_link_list), GFP_KERNEL);
	if (!new_list) {
		SUSFS_LOGE("no enough memory\n");
		return 1;
	}

	memcpy(&new_list->info, &info, sizeof(struct st_susfs_sus_proc_fd_link));
	INIT_LIST_HEAD(&new_list->list);
	spin_lock(&susfs_spin_lock);
	list_add_tail(&new_list->list, &LH_SUS_PROC_FD_LINK);
	spin_unlock(&susfs_spin_lock);

	SUSFS_LOGI("target_link_name: '%s', spoofed_link_name: '%s', is successfully added to LH_SUS_PROC_FD_LINK\n",
		info.target_link_name, info.spoofed_link_name);
	return 0;
}
EXPORT_SYMBOL(susfs_add_sus_proc_fd_link);

/* Called from proc_fd_link show function
 * Returns 1 if link should be spoofed (original pathname replaced)
 */
int susfs_sus_proc_fd_link(const char *pathname, unsigned int max_len)
{
	struct st_susfs_sus_proc_fd_link_list *cursor;

	if (!pathname)
		return 0;

	list_for_each_entry(cursor, &LH_SUS_PROC_FD_LINK, list) {
		if (strstr(pathname, cursor->info.target_link_name)) {
			return 1;
		}
	}
	return 0;
}
EXPORT_SYMBOL(susfs_sus_proc_fd_link);

#endif /* CONFIG_KSU_SUSFS_SUS_PROC_FD_LINK */

/************/
/* SUS_MEMFD */
/************/
#ifdef CONFIG_KSU_SUSFS_SUS_MEMFD

#define SUSFS_MAX_LEN_MFD_NAME 248

struct st_susfs_sus_memfd {
	char                    target_pathname[SUSFS_MAX_LEN_MFD_NAME];
};

struct st_susfs_sus_memfd_list {
	struct list_head                        list;
	struct st_susfs_sus_memfd               info;
};

static LIST_HEAD(LH_SUS_MEMFD);

int susfs_add_sus_memfd(struct st_susfs_sus_memfd __user *user_info)
{
	struct st_susfs_sus_memfd_list *cursor, *temp;
	struct st_susfs_sus_memfd_list *new_list = NULL;
	struct st_susfs_sus_memfd info;

	if (copy_from_user(&info, user_info, sizeof(struct st_susfs_sus_memfd))) {
		SUSFS_LOGE("failed copying from userspace\n");
		return 1;
	}

	list_for_each_entry_safe(cursor, temp, &LH_SUS_MEMFD, list) {
		if (!strcmp(info.target_pathname, cursor->info.target_pathname)) {
			SUSFS_LOGE("memfd name: '%s' is already in LH_SUS_MEMFD\n", info.target_pathname);
			return 1;
		}
	}

	new_list = kmalloc(sizeof(struct st_susfs_sus_memfd_list), GFP_KERNEL);
	if (!new_list) {
		SUSFS_LOGE("no enough memory\n");
		return 1;
	}

	memcpy(&new_list->info, &info, sizeof(struct st_susfs_sus_memfd));
	INIT_LIST_HEAD(&new_list->list);
	spin_lock(&susfs_spin_lock);
	list_add_tail(&new_list->list, &LH_SUS_MEMFD);
	spin_unlock(&susfs_spin_lock);

	SUSFS_LOGI("memfd name: '%s' is successfully added to LH_SUS_MEMFD\n", info.target_pathname);
	return 0;
}
EXPORT_SYMBOL(susfs_add_sus_memfd);

/* Called from sys_memfd_create
 * Returns 1 if the memfd name matches a blocked pattern
 */
int susfs_sus_memfd(const char *name)
{
	struct st_susfs_sus_memfd_list *cursor;

	if (!name)
		return 0;

	list_for_each_entry(cursor, &LH_SUS_MEMFD, list) {
		if (strstr(name, cursor->info.target_pathname)) {
			SUSFS_LOGI("susfs memfd: '%s' blocked by pattern: '%s'\n",
				name, cursor->info.target_pathname);
			return 1;
		}
	}
	return 0;
}
EXPORT_SYMBOL(susfs_sus_memfd);

#endif /* CONFIG_KSU_SUSFS_SUS_MEMFD */

/*********************/
/* SUSFS CMD dispatch */
/*********************/
/* The four handlers above are exported (EXPORT_SYMBOL) so ksu_susfs_compat.c
 * calls them directly from susfs_handle_sys_reboot() under CONFIG_ guards.
 * No local static wrappers — they would be unused and trip -Wunused-function. */
