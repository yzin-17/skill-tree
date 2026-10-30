package skill

import (
	"strings"
	"time"
	"unicode/utf8"

	"skillatlas/internal/apiutil"
)

var Icons = []string{"star", "code", "database", "network", "terminal", "book", "brain", "pencil", "music", "camera", "paint", "language", "heart", "fitness", "leaf", "compass"}
var Themes = []string{"blue", "gold", "sage", "rose"}

type TreeInput struct {
	ID          string `json:"id"`
	Name        string `json:"name"`
	Description string `json:"description"`
	ThemeKey    string `json:"theme_key"`
	SortOrder   int    `json:"sort_order"`
	Archived    bool   `json:"archived"`
	Version     int    `json:"version"`
}
type SkillInput struct {
	ID            string  `json:"id"`
	TreeID        string  `json:"tree_id"`
	ParentSkillID *string `json:"parent_skill_id"`
	Name          string  `json:"name"`
	Description   string  `json:"description"`
	IconKey       string  `json:"icon_key"`
	SortOrder     int     `json:"sort_order"`
	Archived      bool    `json:"archived"`
	Version       int     `json:"version"`
}
type Tree struct {
	ID          string     `json:"id"`
	Name        string     `json:"name"`
	Description string     `json:"description"`
	ThemeKey    string     `json:"theme_key"`
	SortOrder   int        `json:"sort_order"`
	ArchivedAt  *time.Time `json:"archived_at"`
	Version     int        `json:"version"`
	CreatedAt   time.Time  `json:"created_at"`
	UpdatedAt   time.Time  `json:"updated_at"`
}
type Skill struct {
	ID            string     `json:"id"`
	TreeID        string     `json:"tree_id"`
	ParentSkillID *string    `json:"parent_skill_id"`
	Name          string     `json:"name"`
	Description   string     `json:"description"`
	IconKey       string     `json:"icon_key"`
	SortOrder     int        `json:"sort_order"`
	ArchivedAt    *time.Time `json:"archived_at"`
	Version       int        `json:"version"`
	CreatedAt     time.Time  `json:"created_at"`
	UpdatedAt     time.Time  `json:"updated_at"`
}

func has(values []string, value string) bool {
	for _, v := range values {
		if v == value {
			return true
		}
	}
	return false
}
func fields(name *string, description string, order int) error {
	*name = strings.TrimSpace(*name)
	if utf8.RuneCountInString(*name) < 1 || utf8.RuneCountInString(*name) > 80 || utf8.RuneCountInString(description) > 4000 || order < -1000000 || order > 1000000 {
		return apiutil.Fail(400, "invalid_fields", "名称需为 1–80 个字符，描述最多 4000 个字符，排序值超出范围。")
	}
	return nil
}
func (v *TreeInput) Validate(create bool) error {
	if err := fields(&v.Name, v.Description, v.SortOrder); err != nil {
		return err
	}
	if !apiutil.ValidID(v.ID) || !has(Themes, v.ThemeKey) || (create && (v.Version != 0 || v.Archived)) || (!create && v.Version < 1) {
		return apiutil.Fail(400, "invalid_tree", "技能树标识、主题或版本无效。")
	}
	return nil
}
func (v *SkillInput) Validate(create bool) error {
	if err := fields(&v.Name, v.Description, v.SortOrder); err != nil {
		return err
	}
	if !apiutil.ValidID(v.ID) || !apiutil.ValidID(v.TreeID) || !has(Icons, v.IconKey) || (create && (v.Version != 0 || v.Archived)) || (!create && v.Version < 1) {
		return apiutil.Fail(400, "invalid_skill", "技能标识、图标或版本无效。")
	}
	if v.ParentSkillID != nil && (!apiutil.ValidID(*v.ParentSkillID) || *v.ParentSkillID == v.ID) {
		return apiutil.Fail(400, "invalid_parent", "父技能标识无效或指向自身。")
	}
	return nil
}
