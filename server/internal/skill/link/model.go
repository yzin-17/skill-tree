package link

import (
	"skillatlas/internal/apiutil"
	"time"
)

type Input struct {
	ID            string `json:"id"`
	FromSkillID   string `json:"from_skill_id"`
	ToSkillID     string `json:"to_skill_id"`
	LinkType      string `json:"link_type"`
	RequiredLevel *int64 `json:"required_level"`
}
type Link struct {
	Input
	Version   int        `json:"version"`
	CreatedAt time.Time  `json:"created_at"`
	DeletedAt *time.Time `json:"deleted_at"`
}

func (v *Input) Validate() error {
	if !apiutil.ValidID(v.ID) || !apiutil.ValidID(v.FromSkillID) || !apiutil.ValidID(v.ToSkillID) || v.FromSkillID == v.ToSkillID {
		return apiutil.Fail(400, "invalid_link", "关系端点无效或引用了自身。")
	}
	switch v.LinkType {
	case "prerequisite":
		if v.RequiredLevel == nil {
			v.RequiredLevel = new(int64(1))
		}
		if *v.RequiredLevel < 1 || *v.RequiredLevel > 1000000 {
			return apiutil.Fail(400, "invalid_level", "前置等级必须为 1–1000000。")
		}
	case "reference":
		if v.RequiredLevel != nil {
			return apiutil.Fail(400, "invalid_reference", "普通关联不设置前置等级。")
		}
	default:
		return apiutil.Fail(400, "invalid_link_type", "关系类型无效。")
	}
	return nil
}
